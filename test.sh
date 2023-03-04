#!/bin/dash
cd $(dirname "$0")

dub test :message || exit 1
dub test :server || exit 1
dub test :microframework || exit 1

cd examples

cd server
dub build --build=plain || exit 1

cd ../microframework
dub build --build=plain || exit 1

cd ../microframework-quickstart 1
dub build --build=plain || exit 1
