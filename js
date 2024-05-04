#!/bin/bash

_rb $CRUN_PATH/cmdgen.rb node node $@ > .cmdsh

bash .cmdsh
