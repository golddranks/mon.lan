#!/bin/sh -eu

ROOT_PW=${1:?}
SSH_PUBKEY=${2:?}
PPP_ID=${3:?}
PPP_PW=${4:?}
WIFI_PW=${5:?}
GANDI_API_KEY=${6:?}
WG_KEY=${7:?}
WG_PRESHARED_KEY=${8:?}


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


uci set network.wan.proto='pppoe'
uci set network.wan.username="$PPP_ID"
uci set network.wan.password="$PPP_PW"
uci commit network

uci set wireless.default_radio0.ssid='Skeletor 5Ghz'
uci set wireless.default_radio0.key="$WIFI_PW"
uci set wireless.default_radio0.encryption='psk2'
uci set wireless.radio0.disabled='0'
uci set wireless.default_radio1.ssid='Skeletor 2.5Ghz'
uci set wireless.default_radio1.key="$WIFI_PW"
uci set wireless.default_radio1.encryption='psk2'
uci set wireless.radio1.disabled='0'
uci commit wireless

uci set system.@system[0].hostname='mon'
uci set system.@system[0].timezone='Asia/Tokyo'
uci commit system

echo "Basic network config reloaded."

# Set LAN to relay mode to support NDP+RA based addressing
uci set dhcp.lan.ra='relay'
uci set dhcp.lan.dhcpv6='relay'
uci set dhcp.lan.ndp='relay'

# Add WAN6 interface, set it to relay mode and master
uci set dhcp.wan6=dhcp
uci set dhcp.wan6.interface='wan6'
uci set dhcp.wan6.ignore='1'
uci set dhcp.wan6.master='1'
uci set dhcp.wan6.dhcpv6='relay'
uci set dhcp.wan6.ra='relay'
uci set dhcp.wan6.ndp='relay'
uci commit dhcp

# MacO NDP+RA supports only LLA source addresses, so don't use ULA
uci delete network.globals.ula_prefix
uci commit network

echo "IPv6 settings done."


uci add dhcp host
uci set dhcp.@host[-1].name='nagi'
uci set dhcp.@host[-1].mac='A8:A1:59:36:BE:32'
uci set dhcp.@host[-1].ip='192.168.1.10'
uci set dhcp.@host[-1].hostid='10'
uci set dhcp.@host[-1].dns='1'

uci add dhcp host
uci set dhcp.@host[-1].name='poi'
uci set dhcp.@host[-1].mac='C7:92:BC:8A:DC:A6'
uci set dhcp.@host[-1].ip='192.168.1.11'
uci set dhcp.@host[-1].hostid='11'
uci set dhcp.@host[-1].dns='1'
uci commit dhcp

# Remove leases that were made before the static settings
rm /tmp/dhcp.leases

echo "DHCP static lease settings done."


uci add firewall redirect
uci set firewall.@redirect[-1].target='DNAT'
uci set firewall.@redirect[-1].name='SSH'
uci set firewall.@redirect[-1].src='wan'
uci set firewall.@redirect[-1].src_dport='22'
uci set firewall.@redirect[-1].dest='lan'
uci set firewall.@redirect[-1].dest_ip='192.168.1.11'
uci set firewall.@redirect[-1].dest_port='22'
uci commit firewall

echo "Port forwarding settings done."
reload_config

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

openssl req -x509 -nodes -days 730 -key /etc/ssl/mon.lan.key -out /etc/ssl/mon.lan.crt -config /etc/ssl/mon.lan.conf
sed -i -e 's|/etc/nginx/nginx.cer|/etc/ssl/mon.lan.crt|' -e 's|/etc/nginx/nginx.key|/etc/ssl/mon.lan.key|' /etc/nginx/nginx.conf

/etc/init.d/nginx reload

echo "HTTPS enabled on web interface."


uci set wireless.default_radio1.wps_pushbutton='1'
uci commit wireless

opkg remove wpad-basic
opkg install wpad hostapd-utils

echo "WPS settings done."


opkg install http://downloads.openwrt.org/snapshots/packages/mips_24kc/packages/ddns-scripts-services_2.8.2-4_all.ipk
opkg install http://downloads.openwrt.org/snapshots/packages/mips_24kc/packages/ddns-scripts_2.8.2-4_all.ipk
opkg install http://downloads.openwrt.org/snapshots/packages/mips_24kc/packages/ddns-scripts-gandi_2.8.2-4_all.ipk
opkg install http://downloads.openwrt.org/snapshots/packages/mips_24kc/luci/luci-app-ddns_git-20.356.70818-05328b2_all.ipk

uci delete ddns.myddns_ipv4
uci delete ddns.myddns_ipv6
uci -m import ddns << EOF
config service 'poi_ganba_re_4'
	option lookup_host 'poi.ganba.re'
	option domain 'ganba.re'
	option username 'poi'
	option password '$GANDI_API_KEY'
	option interface 'wan'
	option ip_source 'network'
	option ip_network 'wan'
	option update_script '/usr/lib/ddns/update_gandi_net.sh'
	option dns_server 'ns-2-a.gandi.net'
	option enabled '1'

config service 'poi_ganba_re_6'
	option use_ipv6 '1'
	option lookup_host 'poi.ganba.re'
	option domain 'ganba.re'
	option username 'poi'
	option password '$GANDI_API_KEY'
	option interface 'wan6'
	option ip_source 'network'
	option ip_network 'wan6'
	option update_script '/usr/lib/ddns/update_gandi_net.sh'
	option dns_server 'ns-2-a.gandi.net'
	option enabled '1'
EOF
uci commit ddns

echo "DynDNS settings done."


opkg install luci-proto-wireguard luci-app-wireguard
uci set network.wg0=interface
uci set network.wg0.proto='wireguard'
uci set network.wg0.private_key="$WG_KEY"
uci set network.wg0.listen_port='51820'
uci add_list network.wg0.addresses='192.168.99.1'

uci add network wireguard_wg0
uci set network.@wireguard_wg0[-1].description='bae'
uci set network.@wireguard_wg0[-1].public_key='is4/cpRQYOogqZ5wwulRxwaHygDobsZT0jlCyHnF6D4='
uci set network.@wireguard_wg0[-1].preshared_key='$WG_PRESHARED_KEY'
uci add_list network.@wireguard_wg0[-1].allowed_ips='192.168.99.2/32'
uci set network.@wireguard_wg0[-1].route_allowed_ips='1'
uci commit network

uci add_list firewall.cfg02dc81.network='wg0'

echo "Wireguard settings done."


# The luci config file conflicts with the new package
rm /etc/config/luci
opkg list-upgradable | cut -f 1 -d ' ' | xargs opkg upgrade

echo "Base packages upgraded"


opkg install curl nano coreutils-base64 wget

echo "curl & nano installed."

reload_config
echo "Rebooting."
reboot now
