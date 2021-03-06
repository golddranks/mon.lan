#!/bin/sh -eu

. ./secrets.sh

SSH_PUBKEY=$(cat $HOME/.ssh/id_rsa.pub)

# Dropping the host key using SCP because the dropbear format is a binary format
echo "$DROPBEAR_HOST_KEY" | base64 --decode > dropbear_rsa_host_key
scp -o StrictHostKeyChecking=no dropbear_rsa_host_key root@192.168.1.1:/etc/dropbear/dropbear_rsa_host_key
rm dropbear_rsa_host_key
ssh -o StrictHostKeyChecking=no root@192.168.1.1 "/etc/init.d/dropbear restart"

echo "Dropbear restarted."
ssh-keygen -R 192.168.1.1

# x509 certs for the admin panel are also unwieldy to handle so let's SCP them
ssh -o StrictHostKeyChecking=no root@192.168.1.1 "mkdir -p /etc/ssl"
scp cert/mon.lan.key root@192.168.1.1:/etc/ssl/mon.lan.key
scp cert/mon.lan.chain.pem root@192.168.1.1:/etc/ssl/mon.lan.chain.pem

# Sending the install scripts
scp remote1.sh root@192.168.1.1:
scp remote2.sh root@192.168.1.1:
scp ../pubkeys/authorized_keys_strict root@192.168.1.1:
ssh root@192.168.1.1 "./remote1.sh '$ROOT_PW' '$SSH_PUBKEY' '$PPP_ID' '$PPP_PW' '$WIFI_PW'"

# Wait for reboot
while ! ping -c 1 10.0.0.1 ; do sleep 2 ; done
ssh root@mon.lan "./remote2.sh '$GANDI_API_KEY' '$WG_KEY' '$WG_PRESHARED_KEY'"
