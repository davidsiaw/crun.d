#!/bin/bash
# sp - spice server control.
#
# Spice lets sandboxed agents (pa) run heighliner even though they have no
# docker socket of their own. This container has the socket, and runs the real
# heighliner on their behalf.
#
# The image is built and pushed separately; sp only runs it.
#
#   sp up            start the server
#   sp update        pull a newer image and restart onto it
#   sp down          stop it
#   sp status        is it alive, and what does it allow
#   sp logs          follow its output
#   sp env           print the docker flags a sandbox needs to reach it
set -euo pipefail

IMAGE="${SPICE_IMAGE:-davidsiaw/heighliner-spice:latest}"
NAME="${SPICE_NAME:-heighliner-spice}"
PORT="${SPICE_PORT:-7529}"

# Heighliner's own names for its config dir, network and resolver. Asked of the
# image rather than hardcoded, because a kaiser-era install calls them kaiser_*.
# Lazily, so `sp down` and `sp logs` still work with no image to ask.
hl() {
  [ -n "${SPICE_HL_NETWORK:-}" ] || eval "$(_spice)"
  NETWORK="${SPICE_NETWORK:-$SPICE_HL_NETWORK}"
}

# The same answers, stamped onto the container as labels, so pa can read them
# with a `docker inspect` it is already making instead of asking again.
#
# Built into an array directly, one element per flag. Reading them from a
# line-printing function would need `mapfile`, which macOS does not have: its
# /bin/bash is 3.2, and a label value is a path that may contain spaces, so word
# splitting is not an option either.
hl_labels() {
  LABELS=(
    "--label=spice.heighliner.config_dir=$SPICE_HL_CONFIG_DIR"
    "--label=spice.heighliner.network=$SPICE_HL_NETWORK"
    "--label=spice.heighliner.dns=$SPICE_HL_DNS"
    "--label=spice.heighliner.flavor=$SPICE_HL_FLAVOR"
  )
}

# The duplex stream: stdin, window size and exit codes for attach/login/root.
STREAM_PORT="${SPICE_STREAM_PORT:-7530}"

# Deliberately not under heighliner's config dir: that directory is usually
# owned by root, because the heighliner docker alias writes it as root.
TOKEN_FILE="${SPICE_TOKEN_FILE:-$HOME/.local/share/spice/token}"

# The client and its skill are published into a volume straight out of the
# server image, so they can never drift apart from it, and nothing is written to
# the host but the token.
CLIENT_VOLUME="${SPICE_CLIENT_VOLUME:-spice-client}"

# A docker CLI config for the server alone, so it stops reading yours.
#
# $HOME is mounted, so the CLI in the container picks up ~/.docker/config.json --
# which on a Mac says `"credsStore": "desktop"`. That makes it exec
# `docker-credential-desktop`, a macOS binary that does not exist in a Linux
# container, and EVERY image pull dies with:
#
#   error getting credentials - err: exec: "docker-credential-desktop":
#   executable file not found in $PATH
#
# even for public images that need no credentials at all. Same shape as the
# DOCKER_HOST problem: your host config is right for your host and wrong in here.
#
# The fix belongs on this side, not in your config. Editing ~/.docker/config.json
# to drop credsStore would fix the container by moving every registry credential
# you own out of the macOS Keychain and into base64 in a plaintext file -- a real
# security downgrade to work around a path problem.
#
# So: hand the server its own DOCKER_CONFIG containing the parts that travel
# (auths, so private pulls keep working) and not the parts that do not (credsStore,
# credHelpers, currentContext).
SERVER_DOCKER_CONFIG="${SPICE_DOCKER_CONFIG:-$HOME/.local/share/spice/docker}"

write_server_docker_config() {
  mkdir -p "$SERVER_DOCKER_CONFIG" || {
    echo "sp: cannot create $SERVER_DOCKER_CONFIG" >&2
    return 1
  }
  local src="$HOME/.docker/config.json"
  local dst="$SERVER_DOCKER_CONFIG/config.json"

  if [ ! -f "$src" ]; then
    echo '{}' > "$dst"
    return 0
  fi

  # Keep `auths` so an already-logged-in private registry still resolves; drop the
  # helper keys that name host-only executables. python3 ships with macOS and is
  # present on any Linux that runs docker, and this is the one place sp needs to
  # understand JSON rather than shell out to jq.
  if ! python3 - "$src" "$dst" <<'PY'
import json, sys

src, dst = sys.argv[1], sys.argv[2]
try:
    with open(src) as fh:
        cfg = json.load(fh)
except (OSError, ValueError):
    cfg = {}

# auths entries whose value is empty exist only to say "ask the helper", so they
# are useless without it and would still fail. Keep the ones carrying a token.
auths = {k: v for k, v in (cfg.get("auths") or {}).items() if v}

out = {"auths": auths} if auths else {}
with open(dst, "w") as fh:
    json.dump(out, fh)
PY
  then
    echo "sp: could not rewrite docker config; falling back to an empty one" >&2
    echo '{}' > "$dst"
  fi
}

# `stat` is not portable: GNU coreutils takes -c with %-codes, BSD/Darwin takes
# -f with different ones. These run on the HOST, so they must work on whichever
# stat the host ships -- and getting it wrong is quiet, because the error goes to
# stderr inside $( ) and the fallback swallows the failure. That is exactly how
# the docker socket's group went unadded on every Mac for months.
stat_owner() {
  stat -c '%U' "$1" 2>/dev/null || stat -f '%Su' "$1" 2>/dev/null || echo '?'
}

token() {
  if [ ! -s "$TOKEN_FILE" ]; then
    mkdir -p "$(dirname "$TOKEN_FILE")" || { echo "sp: cannot create $(dirname "$TOKEN_FILE")" >&2; return 1; }
    umask 177
    head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$TOKEN_FILE" \
      || { echo "sp: cannot write $TOKEN_FILE" >&2; return 1; }
  fi
  [ -s "$TOKEN_FILE" ] || { echo "sp: $TOKEN_FILE is empty" >&2; return 1; }
  cat "$TOKEN_FILE"
}

publish_client() {
  docker volume inspect "$CLIENT_VOLUME" >/dev/null 2>&1 \
    || docker volume create "$CLIENT_VOLUME" >/dev/null
  # The volume mirrors the repo layout, so the client's ../wire resolves the
  # same in both places.
  docker run --rm -v "$CLIENT_VOLUME:/out" "$IMAGE" sh -c '
    set -e
    rm -rf /out/client /out/wire /out/skills
    cp -R /app/spice/client /out/client
    cp -R /app/spice/wire /out/wire
    cp -R /app/spice/skills /out/skills
    chmod 755 /out/client/heighliner /out/client/kaiser
    chmod -R a+rX /out/client /out/wire /out/skills
  '
  echo "sp: client and skill published to volume $CLIENT_VOLUME"
}

# Spice runs heighliner as the invoking user, so the state directories it writes
# must be owned by that user. The plain `docker run ... davidsiaw/heighliner`
# alias writes them as root, so they can end up unwritable by you.
# Failing here is far kinder than failing later inside an agent, which cannot
# see host paths at all and will misread it as its own permission problem.
check_writable() {
  local bad=0 dir
  # The config dir heighliner reported, not a hardcoded ~/.heighliner: on a
  # kaiser-era install the one it writes is ~/.kaiser.
  for dir in "$SPICE_HL_CONFIG_DIR" "$HOME/.docker"; do
    [ -e "$dir" ] || continue
    [ -w "$dir" ] && continue
    echo "sp: $dir is not writable by $(id -un) (owned by $(stat_owner "$dir"))" >&2
    bad=1
  done
  [ "$bad" -eq 0 ] && return 0

  echo "sp: heighliner runs inside spice as you, so it cannot write its config." >&2
  echo "sp: fix with:  sudo chown -R \"\$(id -u):\$(id -g)\" $SPICE_HL_CONFIG_DIR ~/.docker" >&2
  return 1
}

running() {
  docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null | grep -q true
}

ensure_network() {
  docker network inspect "$NETWORK" >/dev/null 2>&1 || docker network create "$NETWORK" >/dev/null
}

# `up` does not pull an image it already has: starting the server is the thing you
# do most often, and it should not need the network, or a registry having a bad
# day. `update` is how you ask to upgrade.
start() {
  # Resolve the token before docker run: a failure inside $(...) in an
  # argument list does not trip set -e, and would silently start an
  # unauthenticated server.
  TOKEN="$(token)"
  hl
  check_writable
  write_server_docker_config
  ensure_network
  # After any pull, so the published client always matches the server we run.
  publish_client
  docker rm -f "$NAME" >/dev/null 2>&1 || true

  # Run as the invoking user, not root. The server has $HOME bind-mounted, and
  # heighliner shells out to docker/git/buildx inside it -- as root those tools
  # leave root-owned state in ~/.docker, ~/.heighliner and friends, which then
  # breaks the same commands run directly on the host.
  #
  # Reaching the socket as a non-root user needs its group -- and the only place
  # that group number is meaningful is INSIDE a container, so that is where it is
  # asked. `stat` on the host is wrong twice over:
  #
  #   - macOS ships BSD stat, so the GNU `-c` form fails outright (silently, since
  #     the error goes to stderr inside $( ) ), adding no group at all;
  #   - and /var/run/docker.sock on macOS is a SYMLINK into Docker Desktop's VM,
  #     which stat does not follow by default. Measured: the host reports
  #     `0 1 lrwxr-xr-x` (the link, gid 1) while the socket as a container sees it
  #     is `0 0 660`. So even the "fixed" BSD form yielded --group-add 1, which is
  #     a real group and a wrong one -- the failure mode stayed identical.
  #
  # One alpine run answers the question that actually matters, on every platform,
  # with no GNU/BSD branch and no symlink ambiguity.
  #
  # Adding a SUPPLEMENTARY group cannot change what heighliner writes into $HOME:
  # a new file takes the process's PRIMARY gid, which --user still pins to yours.
  # So this buys socket access without reintroducing the root-owned-files problem
  # that --user exists to prevent (see docs/operations.md#file-ownership).
  DOCKER_GID="$(docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    alpine stat -c '%g' /var/run/docker.sock 2>/dev/null | tr -d '\r\n' || echo '')"

  # $HOME is mounted at its real path because pa mounts projects at their real
  # path too. Everything -- this container, the agent's container, and the
  # docker daemon's bind mounts -- must agree on what "/home/you/proj" means.
  #
  # That mount is also why DOCKER_HOST has to be set below. With $HOME visible,
  # the docker CLI reads your ~/.docker/config.json, finds
  # `"currentContext": "desktop-linux"`, and dials that context's endpoint --
  # unix:///Users/you/.docker/run/docker.sock, a host path that does not exist in
  # the container. The socket mounted at /var/run/docker.sock was then simply
  # ignored, and every docker-touching heighliner command failed with "Cannot
  # connect to the Docker daemon". CLI precedence is DOCKER_HOST > context >
  # default, so naming the socket explicitly wins.
  hl_labels

  docker run -d \
    --name "$NAME" \
    --network "$NETWORK" \
    "${LABELS[@]}" \
    --restart unless-stopped \
    --user "$(id -u):$(id -g)" \
    ${DOCKER_GID:+--group-add "$DOCKER_GID"} \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$HOME:$HOME" \
    -e "HOME=$HOME" \
    -e DOCKER_HOST=unix:///var/run/docker.sock \
    -v "$SERVER_DOCKER_CONFIG:/spice-docker" \
    -e DOCKER_CONFIG=/spice-docker \
    -e "SPICE_TOKEN=$TOKEN" \
    -e "SPICE_PORT=$PORT" \
    -e "SPICE_STREAM_PORT=$STREAM_PORT" \
    ${OP_SERVICE_ACCOUNT_TOKEN:+-e "OP_SERVICE_ACCOUNT_TOKEN=$OP_SERVICE_ACCOUNT_TOKEN"} \
    "$IMAGE" >/dev/null
  echo "sp: $NAME up on $NETWORK as $NAME:$PORT (health) and $NAME:$STREAM_PORT (stream)"
}

case "${1:-}" in
  up)
    docker image inspect "$IMAGE" >/dev/null 2>&1 || docker pull "$IMAGE"
    start
    ;;

  update)
    # Always followed by a restart, even when the pull changed nothing. The
    # server, the client and the skill all come out of this one image, so a bare
    # pull would leave the running server on the old image and the client volume
    # on the new one -- the drift the shared image exists to make impossible.
    docker pull "$IMAGE"
    start
    ;;

  down)
    docker rm -f "$NAME" >/dev/null 2>&1 && echo "sp: $NAME down" || echo "sp: $NAME was not running"
    ;;

  status)
    # No ports are published to the host: sandboxes reach spice by name on its
    # docker network, so publishing would be attack surface earning nothing.
    # Ask from inside the container instead.
    running || { echo "sp: not running"; exit 1; }
    docker exec "$NAME" curl -fsS "http://127.0.0.1:$PORT/health" && echo
    hl
    echo "sp: heighliner config in $SPICE_HL_CONFIG_DIR ($SPICE_HL_FLAVOR), network $NETWORK"
    ;;

  logs)
    exec docker logs -f "$NAME"
    ;;

  env)
    # These flags are useless if the server is not actually up: the sandbox
    # would just fail to resolve the hostname.
    hl
    running || echo "sp: warning: $NAME is not running, these flags will not resolve. Run 'sp up'." >&2
    cat <<EOF
--network $NETWORK
-v $CLIENT_VOLUME:/opt/spice:ro
-e SPICE_URL=http://$NAME:$PORT
-e SPICE_STREAM_PORT=$STREAM_PORT
-e SPICE_TOKEN=$(token)
EOF
    ;;

  *)
    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
