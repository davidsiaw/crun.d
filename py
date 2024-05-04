#!/bin/bash

_rb $CRUN_PATH/cmdgen.rb python python $@ > .cmdsh

bash .cmdsh
