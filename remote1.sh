#!/bin/sh -eu

ROOT_PW=${1:?}
SSH_PUBKEY=${2:?}
PPP_ID=${3:?}
PPP_PW=${4:?}
WIFI_PW=${5:?}

. /etc/openwrt_release

echo "Setting up config on TP-Link Archer C7 v2.0/JP. OS: $DISTRIB_DESCRIPTION"

# Add the host pubkey of the installer host
echo "$SSH_PUBKEY" > /etc/dropbear/authorized_keys

# For convenience, add other common pubkeys
cat authorized_keys_strict >> /etc/dropbear/authorized_keys
rm authorized_keys_strict

passwd << EOF
$ROOT_PW
$ROOT_PW
EOF

uci set dropbear.cfg014dd4.RootPasswordAuth='off'
uci set dropbear.cfg014dd4.PasswordAuth='off'
uci set dropbear.cfg014dd4.Interface='lan'
uci commit dropbear

echo "Security config done."


# Lan
uci set network.lan.ipaddr='10.0.0.1'

# Internet
uci set network.wan.proto='pppoe'
uci set network.wan.username="$PPP_ID"
uci set network.wan.password="$PPP_PW"

# IPv6
uci set network.wan6.proto='dhcpv6'
uci set network.wan6.ifaceid='::1'
# MacOS NDP+RA IPv6 address selection supports only LLA source addresses, so don't use ULA:
uci set network.globals.ula_prefix=''
uci commit network

# Set LAN to relay mode to support NDP+RA based IPv6 addressing
uci set dhcp.lan.ra='relay'
uci set dhcp.lan.dhcpv6='relay'
uci set dhcp.lan.ndp='relay'
# Add WAN6 interface, set it to relay mode and master:
uci set dhcp.wan6=dhcp
uci set dhcp.wan6.interface='wan6'
uci set dhcp.wan6.ignore='1'
uci set dhcp.wan6.master='1'
uci set dhcp.wan6.dhcpv6='relay'
uci set dhcp.wan6.ra='relay'
uci set dhcp.wan6.ndp='relay'
uci commit dhcp

# Wifi
uci set wireless.default_radio0.ssid='Skeletor 5Ghz'
uci set wireless.default_radio0.key="$WIFI_PW"
uci set wireless.default_radio0.encryption='psk2'
uci set wireless.radio0.disabled='0'
uci set wireless.radio0.country='JP'
uci set wireless.default_radio1.ssid='Skeletor 2.5Ghz'
uci set wireless.default_radio1.key="$WIFI_PW"
uci set wireless.default_radio1.encryption='psk2'
uci set wireless.radio1.disabled='0'
uci set wireless.radio1.country='JP'
uci commit wireless

# General system settings
uci set system.cfg01e48a.hostname='mon'
uci set system.cfg01e48a.timezone='JST-9'
uci set system.cfg01e48a.zonename='Asia/Tokyo'
uci commit system

echo "Basic network config done."


# Set DHCP static leases
uci set dhcp.mame=host
uci set dhcp.mame.name='mame'
uci set dhcp.mame.mac='08:2E:5F:1B:C5:F0'
uci set dhcp.mame.ip='10.0.0.10'
uci set dhcp.mame.hostid='10'
uci set dhcp.mame.dns='1'

uci set dhcp.poi=host
uci set dhcp.poi.name='poi'
uci set dhcp.poi.mac='DC:A6:32:08:DB:FC'
uci set dhcp.poi.ip='10.0.0.20'
uci set dhcp.poi.hostid='20'
uci set dhcp.poi.dns='1'

uci set dhcp.nagi=host
uci set dhcp.nagi.name='nagi'
uci set dhcp.nagi.mac='A8:A1:59:36:BE:32'
uci set dhcp.nagi.ip='10.0.0.30'
uci set dhcp.nagi.hostid='30'
uci set dhcp.nagi.dns='1'

uci set dhcp.bae=host
uci set dhcp.bae.name='bae'
uci set dhcp.bae.mac='F4:5C:89:AA:C3:DD'
uci set dhcp.bae.ip='10.0.0.40'
uci set dhcp.bae.hostid='40'
uci set dhcp.bae.dns='1'

uci set dhcp.tsugi=host
uci set dhcp.tsugi.name='tsugi'
uci set dhcp.tsugi.mac='CC:E1:D5:6B:1D:82'
uci set dhcp.tsugi.ip='10.0.0.2'
uci set dhcp.tsugi.hostid='2'
uci set dhcp.tsugi.dns='1'
uci commit dhcp

echo "DHCP static lease settings done."

uci set firewall.forward_common_lan=rule
uci set firewall.forward_common_lan.name='Forward IPv6 HTTP(S) & SSH from WAN'
uci set firewall.forward_common_lan.family='ipv6'
uci set firewall.forward_common_lan.src='wan'
uci set firewall.forward_common_lan.dest='*'
uci set firewall.forward_common_lan.dest_port='80 443 22'
uci set firewall.forward_common_lan.target='ACCEPT'

uci set firewall.forward_common_lan=rule
uci set firewall.forward_common_lan.name='Forward IPv6 Syncthing from WAN (mame)'
uci set firewall.forward_common_lan.family='ipv6'
uci set firewall.forward_common_lan.src='wan'
uci set firewall.forward_common_lan.dest='lan'
uci set firewall.forward_common_lan.dest_ip='10.0.0.10'
uci set firewall.forward_common_lan.dest_port='22000'
uci set firewall.forward_common_lan.target='ACCEPT'

uci set firewall.https_mame=redirect
uci set firewall.https_mame.target='DNAT'
uci set firewall.https_mame.name='HTTPS redirect (mame)'
uci set firewall.https_mame.src='wan'
uci set firewall.https_mame.src_dport='443'
uci set firewall.https_mame.dest='lan'
uci set firewall.https_mame.dest_ip='10.0.0.10'
uci set firewall.https_mame.dest_port='443'

uci set firewall.http_mame=redirect
uci set firewall.http_mame.target='DNAT'
uci set firewall.http_mame.name='HTTP redirect (mame)'
uci set firewall.http_mame.src='wan'
uci set firewall.http_mame.src_dport='80'
uci set firewall.http_mame.dest='lan'
uci set firewall.http_mame.dest_ip='10.0.0.10'
uci set firewall.http_mame.dest_port='80'

uci set firewall.syncthing=redirect
uci set firewall.syncthing.target='DNAT'
uci set firewall.syncthing.name='Syncthing redirect (mame)'
uci set firewall.syncthing.src='wan'
uci set firewall.syncthing.src_dport='22000'
uci set firewall.syncthing.dest='lan'
uci set firewall.syncthing.dest_ip='10.0.0.10'
uci set firewall.syncthing.dest_port='22000'

uci set firewall.ssh_poi=redirect
uci set firewall.ssh_poi.target='DNAT'
uci set firewall.ssh_poi.name='SSH redirect (poi)'
uci set firewall.ssh_poi.src='wan'
uci set firewall.ssh_poi.src_dport='999'
uci set firewall.ssh_poi.dest='lan'
uci set firewall.ssh_poi.dest_ip='10.0.0.20'
uci set firewall.ssh_poi.dest_port='22'

uci commit firewall

echo "Port forwarding settings done."


# Remove leases that were made before the static DHCP settings
rm -f /tmp/dhcp.leases
