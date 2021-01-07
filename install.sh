#!/bin/sh -eu

. ./secrets.sh

SSH_PUBKEY=$(cat $HOME/.ssh/id_rsa.pub)

echo "$DROPBEAR_HOST_KEY" | base64 --decode > dropbear_rsa_host_key
scp -o StrictHostKeyChecking=no dropbear_rsa_host_key root@192.168.1.1:/etc/dropbear/dropbear_rsa_host_key
rm dropbear_rsa_host_key
ssh -o StrictHostKeyChecking=no root@192.168.1.1 "/etc/init.d/dropbear restart"

echo "Dropbear restarted."
ssh-keygen -R 192.168.1.1

ssh -o StrictHostKeyChecking=no root@192.168.1.1 "mkdir -p /etc/ssl"
echo "$SSL_PRIVATE_KEY" > mon.lan.key
echo "$SSL_CERT" > mon.lan.crt
scp mon.lan.key root@192.168.1.1:/etc/ssl/mon.lan.key
scp mon.lan.crt root@192.168.1.1:/etc/ssl/mon.lan.crt
rm mon.lan.key
rm mon.lan.crt

scp remote.sh root@192.168.1.1:
ssh root@192.168.1.1 "./remote.sh '$ROOT_PW' '$SSH_PUBKEY' '$PPP_ID' '$PPP_PW' '$WIFI_PW' '$GANDI_API_KEY' '$WG_KEY' '$WG_PRESHARED_KEY'"
