#!/bin/bash

./_rb cmdgen.rb ruby bundle exec ruby $@ > .cmdsh

bash .cmdsh
