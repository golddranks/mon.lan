#!/bin/sh -eu

. ./secrets.sh

SSH_PUBKEY=$(cat $HOME/.ssh/id_rsa.pub)

ssh-keygen -R 192.168.1.1
scp -q remote.sh root@192.168.1.1:
ssh root@192.168.1.1 "./remote.sh '$ROOT_PW' '$SSH_PUBKEY' '$PPP_ID' '$PPP_PW' '$WIFI_PW'"
