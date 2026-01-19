#!/bin/bash

a=`uuidgen | tr -d '-'`

_rb $CRUN_PATH/cmdgen.rb python python $@ > .cmdsh$a

bash .cmdsh$a

rm .cmdsh$a
