#!/bin/bash

a=`uuidgen | tr -d '-'`

_rb $CRUN_PATH/cmdgen.rb ruby bundle exec ruby $@ > .cmdsh$a

bash .cmdsh$a

rm .cmdsh$a
