#!/bin/dash
cd $(dirname "$0")

dub test :message || exit
dub test :server || exit
dub test :microframework || exit

cd examples

cd server
dub build || exit

cd ../microframework
dub build || exit
