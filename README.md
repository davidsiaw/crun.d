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

Environment Variables
---------------------

- `EXPOSE` - you can override the *.ports thing above by going `EXPOSE="8080:80" rb` for example, or disable by going `EXPOSE=" " rb aa`
- `VERSION` - you can override the local *.version by going `VERSION=3.0 rb myscript.rb`
- `NETWORK` - you can override the local *.network by going `NETWORK=host rb myscript.rb`
