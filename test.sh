#!/bin/dash
cd $(dirname "$0")

dub test :message || exit
dub test :server || exit

cd example
dub build
