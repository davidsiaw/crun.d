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
#   sp down          stop it
#   sp status        is it alive, and what does it allow
#   sp logs          follow its output
#   sp env           print the docker flags a sandbox needs to reach it
set -euo pipefail

IMAGE="${SPICE_IMAGE:-davidsiaw/heighliner-spice:latest}"
NAME="${SPICE_NAME:-heighliner-spice}"
NETWORK="${SPICE_NETWORK:-heighliner_net}"
PORT="${SPICE_PORT:-7529}"
# The duplex stream: stdin, window size and exit codes for attach/login/root.
STREAM_PORT="${SPICE_STREAM_PORT:-7530}"

# Deliberately not under ~/.heighliner: that directory is usually owned by root,
# because the heighliner docker alias writes it as root.
TOKEN_FILE="${SPICE_TOKEN_FILE:-$HOME/.local/share/spice/token}"

# The client and its skill are published into a volume straight out of the
# server image, so they can never drift apart from it, and nothing is written to
# the host but the token.
CLIENT_VOLUME="${SPICE_CLIENT_VOLUME:-spice-client}"

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
    chmod 755 /out/client/heighliner
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
  for dir in "$HOME/.heighliner" "$HOME/.docker"; do
    [ -e "$dir" ] || continue
    [ -w "$dir" ] && continue
    echo "sp: $dir is not writable by $(id -un) (owned by $(stat -c '%U' "$dir" 2>/dev/null || echo '?'))" >&2
    bad=1
  done
  [ "$bad" -eq 0 ] && return 0

  echo "sp: heighliner runs inside spice as you, so it cannot write its config." >&2
  echo "sp: fix with:  sudo chown -R \"\$(id -u):\$(id -g)\" ~/.heighliner ~/.docker" >&2
  return 1
}

running() {
  docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null | grep -q true
}

ensure_network() {
  docker network inspect "$NETWORK" >/dev/null 2>&1 || docker network create "$NETWORK" >/dev/null
}

case "${1:-}" in
  up)
    # Resolve the token before docker run: a failure inside $(...) in an
    # argument list does not trip set -e, and would silently start an
    # unauthenticated server.
    TOKEN="$(token)"
    check_writable
    ensure_network
    docker image inspect "$IMAGE" >/dev/null 2>&1 || docker pull "$IMAGE"
    # After the pull, so the published client always matches the server we run.
    publish_client
    docker rm -f "$NAME" >/dev/null 2>&1 || true

    # Run as the invoking user, not root. The server has $HOME bind-mounted, and
    # heighliner shells out to docker/git/buildx inside it -- as root those tools
    # leave root-owned state in ~/.docker, ~/.heighliner and friends, which then
    # breaks the same commands run directly on the host.
    #
    # Reaching the socket as a non-root user needs its group.
    DOCKER_GID="$(stat -c '%g' /var/run/docker.sock 2>/dev/null || echo '')"

    # $HOME is mounted at its real path because pa mounts projects at their real
    # path too. Everything -- this container, the agent's container, and the
    # docker daemon's bind mounts -- must agree on what "/home/you/proj" means.
    docker run -d \
      --name "$NAME" \
      --network "$NETWORK" \
      --restart unless-stopped \
      --user "$(id -u):$(id -g)" \
      ${DOCKER_GID:+--group-add "$DOCKER_GID"} \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v "$HOME:$HOME" \
      -e "HOME=$HOME" \
      -e "SPICE_TOKEN=$TOKEN" \
      -e "SPICE_PORT=$PORT" \
      -e "SPICE_STREAM_PORT=$STREAM_PORT" \
      ${OP_SERVICE_ACCOUNT_TOKEN:+-e "OP_SERVICE_ACCOUNT_TOKEN=$OP_SERVICE_ACCOUNT_TOKEN"} \
      "$IMAGE" >/dev/null
    echo "sp: $NAME up on $NETWORK as $NAME:$PORT (health) and $NAME:$STREAM_PORT (stream)"
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
    ;;

  logs)
    exec docker logs -f "$NAME"
    ;;

  env)
    # These flags are useless if the server is not actually up: the sandbox
    # would just fail to resolve the hostname.
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
    sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
