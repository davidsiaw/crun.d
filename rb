#!/bin/bash

_rb $CRUN_PATH/cmdgen.rb ruby bundle exec ruby $@ > .cmdsh

bash .cmdsh
