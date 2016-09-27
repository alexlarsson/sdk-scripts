#!/bin/sh

cd /srv/gnome-sdk

source ./env.sh

flock lock ./repos.sh --pull-stable --pull-nightly --merge-nightly
