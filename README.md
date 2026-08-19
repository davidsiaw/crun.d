crun.d
======

Use docker to run scripts without mucking around with rbenv rvm pyenv anaconda venv etc.

To use
------

source the .bashrc file

Commands
--------

### ruby
- `bn` - install the bundle
- `rb myscript.rb` run a script
- `be somecommand` run something where ruby exists
- `be irb` run the ruby interpreter

### python
- `pi` - install the requirements.txt
- `py myscript.py` run a script
- `py` run the python interpreter
- `pe somecommand` run something where ruby exists

### node.js
- `jn install` - install the package.json with npm
- `jy` - install package.json with yarn
- `js myscript.js` run a script
- `je node -v` run something where node exists

### rust
- `rz` run something where rust exists
- `rc` run cargo

### pi agent
- `pa` run the pi coding agent in a throwaway sandbox container. It reuses the
  image you already have: it is several gigabytes, and a registry round-trip
  before every session buys nothing most of the time
- `pa update` pull a newer sandbox image. This is how you update pi: pi is baked
  into the image, so its own `update` would upgrade something the container
  throws away on exit
- `sp` run the spice server, so a sandboxed agent can use heighliner
- `sp update` pull a newer spice image and restart the server onto it
- `_spice` ask the spice image what heighliner calls its config dir, network and
  containers. Like `cmdgen.rb`, it exists so `sp` and `pa` stay short: the names
  differ on an install predating the heighliner/kaiser rename, and the answer
  comes from heighliner itself rather than from these scripts

`pa` is different from the others: it runs the prebuilt `davidsiaw/pi-sandbox`
image (pulled from Docker Hub, built separately) rather than a stock language
image. It mounts the current directory at its real path and drops you into pi.
Anything the agent installs (gems, npm, pip, extra language runtimes) stays in
the container and vanishes on exit; your project edits and any skills/extensions
the agent writes persist on the host. Runtimes are managed by mise and cached in
a docker volume so you only compile ruby/python once.

```
cd ~/some/project && pa
```

Full docs live with the image at `~/work/picon/docs`.

Customize
---------

### .ruby.version

write the version of ruby you want. versions of ruby are basically the tags available in https://hub.docker.com/_/ruby

### .ruby.ports

write the ports you want to expose. for example to expose 8080 to 80, `8080:80` and to expose 4567 to 4567 `4567:4567`

### .ruby.network

write the network you want your container to be in. This is the equivalent of docker's --network parameter. If you want to use the host
network simply go `host` or use whichever network you have created.

### .ruby.prepare

sometimes you need to apt get something for your script to work. in this case you can write a .ruby.prepare like this:

```
#! /bin/bash

apt get install mylib-dev
```

if you realize you are using a stale image, you can force recreation by going `NOCACHE=1`

### .ruby.x11.json

sometimes you need access to X11 for UI purposes. Use this to connect. you need to fill it with at least `{}` for it to work.

### .ruby.env

sometimes you need to pass environment variables to your application. This can be done by creating the above file and writing in this format:

```
MY_ENV_VAR=abcd
```

### .ruby.openv.yml

sometimes the environment variable you wish to pass is secret. crun supports the use of 1password for this. Here is an example `*.openv.yml`. You will need to install and activate the 1password CLI to enable this.

Only CAPS_CASE keys are read as keys. others are ignored and can be used as aliases.

```
---
awesome_team_vault: &awesome_team_vault
  vault: abcd1234efgh5678uuid

VERY_SECRET_VARIABLE:
  <<: *awesome_team_vault
  item: top-secret-app-credentials
  key: highly-confidential-password
```

The `vault` key is optional but we recommend using it so you have no ambiguity. Tip here is to just encode the vault UUID, so you can have super-readable vault names. `item` key can also be a UUID too!


### How about python and node?

the above things are available for python and node too! Just go .python.ports or .node.network

### pa config

`pa` reads its config from `~/.pi/agent` (your global pi home), not from local
`.pa.*` files, because the sandbox is about pi itself rather than a per-project
language runtime.

What it mounts if present: your `skills/` and `extensions/` (read-write, so the
agent's work is saved), `settings.json` / `models.json` / `trust.json` (read
only), `auth.json` (read only, so pi can reach a model), and any prompt/context
files (`AGENTS.md`, `CLAUDE.md`, `SYSTEM.md`, `APPEND_SYSTEM.md`).

The image can also ship its own skills and extensions (baked at `/opt/pa`),
loaded on top of your host ones. Those live in the image repo, not here.

Private pi packages come from disk instead of from git, because the sandbox has
no ssh keys (a `git:git@github.com:...` entry in `packages` fails, and should:
cloning into a container that is deleted on exit is pointless). List host
checkouts in `PA_PACKAGES` (`:`- or `,`-separated) or one per line in
`~/.pi/agent/pa.packages`; each is mounted **read-only** at
`/opt/pa/local-packages/<name>-<n>` and loaded with `pi -e`, which picks up that
package's extensions *and* skills in one flag. Nothing is copied into
`~/.pi/agent`, so your pi home stays clean. To edit such a package, run `pa`
inside its checkout.

pi sessions are written to a `.pi-sessions/` folder inside the current project
(created by `pa`, passed via `--session-dir`), so they persist on the host and
stay with the project rather than in the throwaway container home.

Secrets/env vars are forwarded, not mounted, from two sources (later wins):

- `~/.pi/agent/pa.env` - plain `KEY=value` lines, e.g. `MY_ENV_VAR=some-value`
- `~/.pi/agent/pa.openv` - live 1password lookups, one per line, same idea as
  crun's `.openv` but line-format: `ENVNAME=item:field` or
  `ENVNAME=item:field:vault`. Needs the `op` CLI signed in; the secret is
  pulled at launch and never written to disk.

Environment Variables
---------------------

- `EXPOSE` - you can override the *.ports thing above by going `EXPOSE="8080:80" rb` for example, or disable by going `EXPOSE=" " rb aa`
- `VERSION` - you can override the local *.version by going `VERSION=3.0 rb myscript.rb`
- `NETWORK` - you can override the local *.network by going `NETWORK=host rb myscript.rb`

### pa toggles

- `PA_IMAGE` - override the image (default `davidsiaw/pi-sandbox:latest`)
- `MOUNT_AUTH=0` - don't mount `auth.json`; keep credentials out of the sandbox
- `NO_MOUNT_SYSTEM=1` - don't mount a host `SYSTEM.md` (which would replace pi's
  system prompt)
- `MISE_VOLUME` - name of the runtime cache volume (default `pi-sandbox-mise`)
- `PA_PACKAGES` - host pi-package checkouts to mount read-only and load for this
  run, e.g. `PA_PACKAGES=~/work/private-pi-ext pa`
