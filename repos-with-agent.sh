#!/bin/sh

gpg-agent --default-cache-ttl=7200 --homedir /srv/gnome-sdk/gnupg --daemon ./repos.sh "$@"
