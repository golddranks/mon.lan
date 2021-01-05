#!/bin/sh -eu

. ./secrets.sh

SSH_PUBKEY=$(cat $HOME/.ssh/id_rsa.pub)

echo "$DROPBEAR_HOST_KEY" | base64 -d > dropbear_rsa_host_key
ssh-keygen -R 192.168.1.1
scp -o StrictHostKeyChecking=no -q dropbear_rsa_host_key root@192.168.1.1:/etc/dropbear/dropbear_rsa_host_key
rm dropbear_rsa_host_key


echo "$SSL_PRIVATE_KEY" > mon.lan.key
scp mon.lan.key root@192.168.1.1:/etc/ssl/mon.lan.key
rm mon.lan.key

scp remote.sh root@192.168.1.1:
ssh root@192.168.1.1 "./remote.sh '$ROOT_PW' '$SSH_PUBKEY' '$PPP_ID' '$PPP_PW' '$WIFI_PW' '$GANDI_API_KEY' '$WG_KEY' '$WG_PRESHARED_KEY'"
