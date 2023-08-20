#!/bin/sh -eu

CURRENT_IP=${1:-192.168.1.1}
CURRENT_PORT=${2:-22}

[ ! -d "../certs" ] && echo "Prepare ../certs directory" && exit 1
[ ! -d "../pubkeys" ] && echo "Prepare ../pubkeys directory" && exit 1

. ./utils.sh
. ./secrets.sh
SSH_PUBKEY=$(cat "$HOME/.ssh/id_rsa.pub")

# Sending the host key with SCP because the dropbear format is a binary format
echo "$DROPBEAR_HOST_KEY" | base64 --decode > dropbear_ed25519_host_key
echo "Attempting to connect."
scpp -o StrictHostKeyChecking=no dropbear_ed25519_host_key \
    "root@${CURRENT_IP}:/etc/dropbear/dropbear_ed25519_host_key"
rm dropbear_ed25519_host_key
sshp -o StrictHostKeyChecking=no "root@${CURRENT_IP}" "/etc/init.d/dropbear restart"

echo "Dropbear restarted."
ssh-keygen -R "${CURRENT_IP}"
# Logging in once to re-set the correct key on this host
sshp -o StrictHostKeyChecking=no "root@${CURRENT_IP}" "echo Works!"

# x509 certs for the admin panel are also unwieldy so let's SCP them
sshp "root@${CURRENT_IP}" "mkdir -p /etc/ssl"
scpp ../certs/cert/mon.lan.key "root@${CURRENT_IP}:/etc/ssl/mon.lan.key"
scpp ../certs/cert/mon.lan.chain.pem "root@${CURRENT_IP}:/etc/ssl/mon.lan.chain.pem"

# Sending the install script
sshp "root@${CURRENT_IP}" "mkdir -p \$HOME/install"
scpp utils.sh remote.sh wireguard.sh ddns.sh mwan.sh "root@${CURRENT_IP}:install"

# Sending the authorized pub keys
scpp ../pubkeys/authorized_keys_strict "root@${CURRENT_IP}:"

# Running the install script
sshp "root@${CURRENT_IP}" "install/remote.sh '$ROOT_PW' '$SSH_PUBKEY' '$PPP_ID' '$PPP_PW' '$WIFI_PW'"
sshp "root@${CURRENT_IP}" "install/wireguard.sh '$WG_KEY' '$WG_PRESHARED_KEY' '$WG_LAN_PEERS' '$WG_DMZ_PEERS'"
sshp "root@${CURRENT_IP}" "install/ddns.sh '$GANDI_API_KEY'"
sshp "root@${CURRENT_IP}" install/mwan.sh

echo "Booting."
sshp "root@${CURRENT_IP}" "reboot now"
