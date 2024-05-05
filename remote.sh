#!/bin/sh -eu

. "${0%/*}/utils.sh"

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

rename_uci_key dropbear cfg014dd4 lan_admin
uci set dropbear.lan_admin.RootPasswordAuth='off'
uci set dropbear.lan_admin.PasswordAuth='off'
uci set dropbear.lan_admin.Interface='lan'
uci set dropbear.lan_admin.Port='222'
uci commit dropbear

echo "Security config done."


# Lan
uci set network.lan.ipaddr='10.0.0.1'


# Vlan
delete_uci_key network.cfg081ec7
delete_uci_key network.cfg091ec7

# LAN VLAN 1 (LAN1 + LAN2 + LAN3 + LAN4 + ETH1)
uci set network.vlan=switch_vlan
uci set network.vlan.description='Internal VLAN (1.1)'
uci set network.vlan.device='switch0'
uci set network.vlan.vlan='1'
uci set network.vlan.ports='0t 2 3 4 5t'

# BIGLOBE VLAN 2 (WAN + ETH0)
uci set network.vwan_bg=switch_vlan
uci set network.vlan.description='BIGLOBE WAN (0.2)'
uci set network.vwan_bg.device='switch0'
uci set network.vwan_bg.vlan='2'
uci set network.vwan_bg.ports='1 6t'

# JCOM WAN VLAN 3 (LAN4 + ETH0)
uci set network.vwan_jc=switch_vlan
uci set network.vlan.description='JCOM WAN (0.3)'
uci set network.vwan_jc.device='switch0'
uci set network.vwan_jc.vlan='3'
uci set network.vwan_jc.ports='5t 6t'

# Internet

# BIGLOBE
rename_uci_key network wan wan_bg
uci set network.wan_bg=interface
uci set network.wan_bg.device='eth0.2'
uci set network.wan_bg.proto='pppoe'
uci set network.wan_bg.username="$PPP_ID"
uci set network.wan_bg.password="$PPP_PW"
uci set network.wan_bg.metric='20'

# JCOM
uci set network.wan_jc=interface
uci set network.wan_jc.device='eth0.3'
uci set network.wan_jc.proto='dhcp'
uci set network.wan_jc.metric='10'

# IPv6
delete_uci_key network.wan6
uci set network.wan_bg6=interface
uci set network.wan_bg6.device='eth0.2'
uci set network.wan_bg6.proto='dhcpv6'
uci set network.wan_bg6.ifaceid='::1'

# Firewall
rename_uci_key firewall cfg03dc81 wan_zone
rename_uci_key firewall cfg02dc81 lan_zone
uci set firewall.wan_zone.network='wan_bg wan_jc wan_bg6'
uci commit firewall

# MacOS NDP+RA IPv6 address selection supports only LLA source addresses, so don't use ULA:
uci set network.globals.ula_prefix=''
uci commit network

# Set LAN to relay mode to support NDP+RA based IPv6 addressing
uci set dhcp.lan.ra='relay'
uci set dhcp.lan.dhcpv6='relay'
uci set dhcp.lan.ndp='relay'

# Add WAN IP6 interface, set it to relay mode and master:
uci set dhcp.wan_bg6=dhcp
uci set dhcp.wan_bg6.interface='wan_bg6'
uci set dhcp.wan_bg6.ignore='1'
uci set dhcp.wan_bg6.master='1'
uci set dhcp.wan_bg6.dhcpv6='relay'
uci set dhcp.wan_bg6.ra='relay'
uci set dhcp.wan_bg6.ndp='relay'
uci commit dhcp

# Wifi
uci set wireless.default_radio0.ssid='Skeletor 5Ghz'
uci set wireless.default_radio0.key="$WIFI_PW"
uci set wireless.default_radio0.encryption='psk2'
uci set wireless.radio0.disabled='0'
uci set wireless.radio0.country='JP'
uci set wireless.default_radio0.ieee80211r='1'
uci set wireless.default_radio0.mobility_domain='cc66'
uci set wireless.default_radio0.ft_over_ds='1'
uci set wireless.default_radio0.ft_psk_generate_local='1'
uci set wireless.radio0.cell_density='0'

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
uci set dhcp.tsugi=host
uci set dhcp.tsugi.name='tsugi'
uci set dhcp.tsugi.mac='CC:E1:D5:6B:1D:82'
uci set dhcp.tsugi.ip='10.0.0.2'
uci set dhcp.tsugi.hostid='2'
uci set dhcp.tsugi.dns='1'

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

uci commit dhcp


GLOBAL_IPV6_PREFIX=$(get_global_ipv6_prefix)
echo "Global IPv6 prefix: ${GLOBAL_IPV6_PREFIX}"

grep mon /etc/hosts || echo "${GLOBAL_IPV6_PREFIX}::1	mon" >> /etc/hosts
# Not a static DHCP lease, but just a static hostname
grep jaska /etc/hosts || echo "10.0.0.2	jaska
${GLOBAL_IPV6_PREFIX}::2	jaska" >> /etc/hosts
grep mame /etc/hosts || echo "${GLOBAL_IPV6_PREFIX}::10	mame" >> /etc/hosts
grep poi /etc/hosts || echo "${GLOBAL_IPV6_PREFIX}::20	poi" >> /etc/hosts

echo "DHCP static lease settings done."

uci set firewall.forward_ipv6_common=rule
uci set firewall.forward_ipv6_common.name='Forward IPv6 HTTP(S) & SSH from WAN'
uci set firewall.forward_ipv6_common.family='ipv6'
uci set firewall.forward_ipv6_common.src='wan'
uci set firewall.forward_ipv6_common.dest='*'
uci set firewall.forward_ipv6_common.dest_port='80 443 22'
uci set firewall.forward_ipv6_common.target='ACCEPT'

uci set firewall.forward_ipv6_syncthing=rule
uci set firewall.forward_ipv6_syncthing.name='Forward IPv6 Syncthing from WAN (mame)'
uci set firewall.forward_ipv6_syncthing.family='ipv6'
uci set firewall.forward_ipv6_syncthing.src='wan'
uci set firewall.forward_ipv6_syncthing.dest='lan'
uci set firewall.forward_ipv6_syncthing.dest_ip="${GLOBAL_IPV6_PREFIX}::10"
uci set firewall.forward_ipv6_syncthing.dest_port='22000'
uci set firewall.forward_ipv6_syncthing.target='ACCEPT'

uci set firewall.https_mame=redirect
uci set firewall.https_mame.target='DNAT'
uci set firewall.https_mame.name='HTTPS IPv4 redirect (mame)'
uci set firewall.https_mame.src='wan'
uci set firewall.https_mame.src_dport='443'
uci set firewall.https_mame.dest='lan'
uci set firewall.https_mame.dest_ip='10.0.0.10'
uci set firewall.https_mame.dest_port='443'

uci set firewall.http_mame=redirect
uci set firewall.http_mame.target='DNAT'
uci set firewall.http_mame.name='HTTP IPv4 redirect (mame)'
uci set firewall.http_mame.src='wan'
uci set firewall.http_mame.src_dport='80'
uci set firewall.http_mame.dest='lan'
uci set firewall.http_mame.dest_ip='10.0.0.10'
uci set firewall.http_mame.dest_port='80'

uci set firewall.syncthing=redirect
uci set firewall.syncthing.target='DNAT'
uci set firewall.syncthing.name='Syncthing IPv4 redirect (mame)'
uci set firewall.syncthing.src='wan'
uci set firewall.syncthing.src_dport='22000'
uci set firewall.syncthing.dest='lan'
uci set firewall.syncthing.dest_ip='10.0.0.10'
uci set firewall.syncthing.dest_port='22000'

uci commit firewall

echo "Port forwarding settings done."


echo "Start installing external packages."

update_opkg

echo "Updated package list."

opkg install curl nano coreutils-base64 wget bind-dig tcpdump ip-full diffutils iperf3 ncat

echo "Utilities installed."


# Install nginx to support performant HTTPS admin panel
opkg install luci-ssl-nginx

delete_uci_key nginx._lan.listen
delete_uci_key nginx._lan.uci_manage_ssl
uci add_list nginx._lan.listen='666 ssl default_server'
uci add_list nginx._lan.listen='[::]:666 ssl default_server'
uci set nginx._lan.ssl_certificate='/etc/ssl/mon.lan.chain.pem'
uci set nginx._lan.ssl_certificate_key='/etc/ssl/mon.lan.key'
mv -n /etc/nginx/restrict_locally /etc/nginx/restrict_locally.original
echo "	allow ${GLOBAL_IPV6_PREFIX}::/64;" > /etc/nginx/restrict_locally
cat /etc/nginx/restrict_locally.original >> /etc/nginx/restrict_locally

uci commit nginx

echo "HTTPS enabled on web interface."


# Set up WPS
# It doesn't seem to work with two radios, so setting up only the 2.5Ghz one.
opkg remove wpad-basic-mbedtls
opkg install wpad-mbedtls hostapd-utils

uci set wireless.default_radio1.wps_pushbutton='1'
uci commit wireless

# NOTE: wlan1 is 2.5Ghz in case of Mon!
cat << EOF > /root/wps.sh
#!/bin/sh
hostapd_cli -i wlan1 wps_pbc
hostapd_cli -i wlan1 wps_get_status
EOF
chmod 0755 /root/wps.sh

echo "WPS settings done."

# Factory reset
cat << EOF > /root/reset.sh
#!/bin/sh
firstboot
reboot
EOF
chmod 0755 /root/reset.sh

# Remove leases that were made before the static DHCP settings
rm -f /tmp/dhcp.leases
