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

Customize
---------

### .ruby.version

write the version of ruby you want. versions of ruby are basically the tags available in https://hub.docker.com/_/ruby

### .ruby.ports

write the ports you want to expose. for example to expose 8080 to 80, `8080:80` and to expose 4567 to 4567 `4567:4567`

### .python.version

write the version of python you want. versions of python are basically the tags available in https://hub.docker.com/_/python

### .python.ports

write the ports you want to expose. for example to expose 8080 to 80, `8080:80` and to expose 4567 to 4567 `4567:4567`

### .node.version

write the version of node you want. versions of node are basically the tags available in https://hub.docker.com/_/node

### .node.ports

write the ports you want to expose. for example to expose 8080 to 80, `8080:80` and to expose 4567 to 4567 `4567:4567`

Environment Variables
---------------------

- `EXPOSE` - you can override the *.ports thing above by going `EXPOSE="8080:80" rb` for example, or disable by going `EXPOSE=" " rb aa`
- `VERSION` - you can override the local *.version by going `VERSION=3.0 rb myscript.rb`
