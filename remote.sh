#!/bin/sh -eu

ROOT_PW=${1:?}
SSH_PUBKEY=${2:?}
PPP_ID=${3:?}
PPP_PW=${4:?}
WIFI_PW=${5:?}

echo "Setting up config on TP-Link Archer C7 v2.0/JP. OS: OpenWrt 19.07.5."

echo "$SSH_PUBKEY" > /etc/dropbear/authorized_keys

# For convenience, add nagi and bae regardless
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQD7vzA+j56GjMFydRotjaCopjJUYDpiNgMw6uTpt2x7LisjY+fZR4uHJlcGpT7ooUROJPTekDyINcdRmhPTc0wg/G4MpeWfUhU8AkjXYhSpgGkh8Q56X4Qh120MG3oSm/FTHjobKaALJHuigiylQc8/G0GHh8Lzh5W/K1c7LZ6/EGCIHwBbJcjAPGQXJtjPOs8b68AK9TnXUAT3DR2cOUOraDTgRQuav63kbz4l7DHKpWXSBwNsw8v2UbL9Yedd677/MNeckmwA4yXe6Sx/4rqufV+5Sin1PGIJsOXc5AiwowcYQNDflbJqaC9UZiTu0ZSLoOV+QUvd4HsDACTVg/lCUDpzmsKFMZzk2lnd4XsLetRBx8rN3HVECxU+nRM05CyAAdL1OYlRN1amiM8XQ6S+FoB16k41e3XTjrhgxu+1hWt+vvlB61QTrI+5xTG3ra555mOzf98MrAzG7A0QONuGOvHtNT49dC2GcgXzHn0N3ntYgOECrpVrXJ+CLHh/LSc= kon@nagi" >> /etc/dropbear/authorized_keys
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDrhFzEaTWS9G/T+rLdGpqcIHevzFMypO7HuVd9/qMiX6G64oveaYBjgRriNricAB+koxKP2Kga6lB5NUVyTaqVN96cVwA9EQJ6GJAi5qZElWVZ7sjODgjVcXdzXSWfztbBLntgxx3J9Ugofy2lb4edGXO7lHqTUI4pmxE6QdIESjVdEUljHsX8uSBOiNXvgQ/TyvStEPp0R8GrKI4fTb+SSQCPn/NYrWFip4OMkqwp98wqqzT5WHi1p0rFzwedyH3SIdic0PCszoSdgRNL9j5AwQ6oXJC0gp5i+8etzyIkCp12o0LBVyWUQaYvH9MujR40p6kZKboUnlXxJ25EWnT5 kon@bae" >> /etc/dropbear/authorized_keys

passwd << EOF
$ROOT_PW
$ROOT_PW
EOF

uci set dropbear.@dropbear[0].RootPasswordAuth='off'
uci set dropbear.@dropbear[0].PasswordAuth='off'
uci commit dropbear

reload_config
echo "Security config reloaded."

uci batch << EOF
set network.wan.proto='pppoe'
set network.wan.username="$PPP_ID"
set network.wan.password="$PPP_PW"
commit network

set wireless.default_radio0.ssid='Skeletor 5Ghz'
set wireless.default_radio0.key="$WIFI_PW"
set wireless.default_radio0.encryption='psk2'
set wireless.radio0.disabled='0'
set wireless.default_radio1.ssid='Skeletor 2.5Ghz'
set wireless.default_radio1.key="$WIFI_PW"
set wireless.default_radio1.encryption='psk2'
set wireless.radio1.disabled='0'
commit wireless

set system.@system[0].hostname='mon'
set system.@system[0].timezone='Asia/Tokyo'
commit system
EOF

reload_config
echo "Basic network config reloaded."

opkg update
opkg install luci-ssl-nginx

cat << EOF > /etc/ssl/mon.lan.conf
[req]
distinguished_name  = req_distinguished_name
x509_extensions     = v3_req
prompt              = no
string_mask         = utf8only

[req_distinguished_name]
C                   = JP
L                   = Tokyo
CN                  = mon.lan

[v3_req]
keyUsage            = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage    = serverAuth
subjectAltName      = @alt_names

[alt_names]
DNS.1               = mon.lan
IP.1                = 192.168.1.1
EOF

openssl req -x509 -nodes -days 730 -newkey rsa:2048 -keyout /etc/ssl/mon.lan.key -out /etc/ssl/mon.lan.crt -config /etc/ssl/mon.lan.conf
sed -i -e 's|/etc/nginx/nginx.cer|/etc/ssl/mon.lan.crt|' -e 's|/etc/nginx/nginx.key|/etc/ssl/mon.lan.key|' /etc/nginx/nginx.conf

service nginx reload

echo "HTTPS enabled on web interface."

uci set network.wan6.proto='none'
uci -m import dhcp << EOF
config dhcp 'wan6'
	option interface 'wan6'
	option ignore '1'
	option dhcpv6 'relay'
	option ra 'relay'
	option ndp 'relay'
	option master '1'
EOF
uci commit network dhcp

reload_config
echo "IPv6 settings done."

# set IPv6
# set DHCP ranges
# wireguard
# set up dyndns
# set up port forwarding
# set up UPnP?
# set up wifi one-push
