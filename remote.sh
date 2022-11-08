#!/bin/sh -eu

ROOT_PW=${1:?}
SSH_PUBKEY=${2:?}
PPP_ID=${3:?}
PPP_PW=${4:?}
WIFI_PW=${5:?}
GANDI_API_KEY=${6:?}
WG_KEY=${7:?}
WG_PRESHARED_KEY=${8:?}

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
uci set dropbear.cfg014dd4.Port='222'
uci commit dropbear

echo "Security config done."


# Lan
uci set network.lan.ipaddr='10.0.0.1'


# Vlan
uci delete network.cfg081ec7 || true
uci delete network.cfg091ec7 || true

# LAN VLAN 1 (LAN1 + LAN2 + LAN3 + LAN4 + ETH1)
uci set network.vlan=switch_vlan
uci set network.vlan.device='switch0'
uci set network.vlan.vlan='1'
uci set network.vlan.ports='0t 2 3 4 5t'

# BIGLOBE VLAN 2 (WAN + ETH0)
uci set network.vwan_bg=switch_vlan
uci set network.vwan_bg.device='switch0'
uci set network.vwan_bg.vlan='2'
uci set network.vwan_bg.ports='1 6t'

# JCOM WAN VLAN 3 (LAN4 + ETH0)
uci set network.vwan_jc=switch_vlan
uci set network.vwan_jc.device='switch0'
uci set network.vwan_jc.vlan='3'
uci set network.vwan_jc.ports='5t 6t'

# Internet

# BIGLOBE
uci set network.wan.proto='pppoe'
uci set network.wan.username="$PPP_ID"
uci set network.wan.password="$PPP_PW"
uci set network.wan.metric='20'

# JCOM
uci set network.wan2=interface
uci set network.wan2.proto='dhcp'
uci set network.wan2.device='eth0.3'
uci set network.wan2.metric='10'
uci set firewall.cfg03dc81.network='wan wan2 wan6'
uci commit firewall

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

# Not a static DHCP lease, but just a static hostname
echo "10.0.0.2	jaska" >> /etc/hosts

echo "DHCP static lease settings done."


GLOBAL_IPV6_PREFIX=$(ip -6 a show dev eth0.2 scope global | grep -o -E ' \w+:\w+:\w+:\w+:')
echo "Global IPv6 prefix: ${GLOBAL_IPV6_PREFIX}"

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
uci set firewall.forward_ipv6_syncthing.dest_ip="${GLOBAL_IPV6_PREFIX}:10"
uci set firewall.forward_ipv6_syncthing.dest_port='22000'
uci set firewall.forward_ipv6_syncthing.target='ACCEPT'

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

uci commit firewall

echo "Port forwarding settings done."


echo "Start installing external packages."

opkg update

echo "Updated package list."

opkg install curl nano coreutils-base64 wget bind-dig tcpdump ip-full diffutils iperf3

echo "Utilities installed."


# Install nginx to support performant HTTPS admin panel
opkg install luci-ssl-nginx

uci delete nginx._lan.listen || true
uci delete nginx._lan.uci_manage_ssl || true
uci add_list nginx._lan.listen='666 ssl default_server'
uci add_list nginx._lan.listen='[::]:666 ssl default_server'
uci set nginx._lan.ssl_certificate='/etc/ssl/mon.lan.chain.pem'
uci set nginx._lan.ssl_certificate_key='/etc/ssl/mon.lan.key'

uci commit nginx

echo "HTTPS enabled on web interface."


# Set up WPS
# It doesn't seem to work with two radios, so setting up only the 2.5Ghz one.
opkg remove wpad-basic-wolfssl
opkg install wpad-wolfssl hostapd-utils

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


# Set up dynamic DNS (Gandi)
opkg install luci-app-ddns ddns-scripts-gandi

# Remove placeholder settings
uci delete ddns.myddns_ipv4 || true
uci delete ddns.myddns_ipv6 || true
uci -m import ddns << EOF
config service 'drasa_eu_ipv4'
	option enabled '1'
	option use_ipv6 '0'
	option service_name 'gandi.net'
	option lookup_host 'drasa.eu'
	option domain 'drasa.eu'
	option username '@'
	option password '$GANDI_API_KEY'
	option ip_source 'network'
	option ip_network 'wan'
	option interface 'wan'
	option use_syslog '2'
	option check_unit 'minutes'
	option force_unit 'minutes'
	option retry_unit 'seconds'

config service 'bitwarden_ipv4'
	option enabled '1'
	option use_ipv6 '0'
	option service_name 'gandi.net'
	option lookup_host 'bitwarden.drasa.eu'
	option domain 'drasa.eu'
	option username 'bitwarden'
	option password '$GANDI_API_KEY'
	option ip_source 'network'
	option ip_network 'wan'
	option interface 'wan'
	option use_syslog '2'
	option check_unit 'minutes'
	option force_unit 'minutes'
	option retry_unit 'seconds'

config service 'syncthing_ipv4'
	option enabled '1'
	option use_ipv6 '0'
	option service_name 'gandi.net'
	option lookup_host 'syncthing.drasa.eu'
	option domain 'drasa.eu'
	option username 'syncthing'
	option password '$GANDI_API_KEY'
	option ip_source 'network'
	option ip_network 'wan'
	option interface 'wan'
	option use_syslog '2'
	option check_unit 'minutes'
	option force_unit 'minutes'
	option retry_unit 'seconds'

config service 'webshare_ipv4'
	option enabled '1'
	option use_ipv6 '0'
	option service_name 'gandi.net'
	option lookup_host 'webshare.drasa.eu'
	option domain 'drasa.eu'
	option username 'webshare'
	option password '$GANDI_API_KEY'
	option ip_source 'network'
	option ip_network 'wan'
	option interface 'wan'
	option use_syslog '2'
	option check_unit 'minutes'
	option force_unit 'minutes'
	option retry_unit 'seconds'

config service 'drasa_eu_ipv6'
	option enabled '1'
	option use_ipv6 '1'
	option service_name 'gandi.net'
	option lookup_host 'drasa.eu'
	option domain 'drasa.eu'
	option username '@'
	option password '$GANDI_API_KEY'
	option ip_source 'network'
	option ip_interface 'wan6'
	option interface 'wan6'
	option use_syslog '2'
	option check_unit 'minutes'
	option force_unit 'minutes'
	option retry_unit 'seconds'

config service 'drasa_eu_jcom'
	option enabled '1'
	option use_ipv6 '0'
	option service_name 'gandi.net'
	option lookup_host 'jcom.drasa.eu'
	option domain 'drasa.eu'
	option username 'jcom'
	option password '$GANDI_API_KEY'
	option ip_source 'network'
	option ip_network 'wan2'
	option interface 'wan2'
	option use_syslog '2'
	option check_unit 'minutes'
	option force_unit 'minutes'
	option retry_unit 'seconds'

config service 'don_ganba_re'
	option enabled '1'
	option use_ipv6 '0'
	option service_name 'gandi.net'
	option lookup_host 'don.ganba.re'
	option domain 'ganba.re'
	option username 'don'
	option password '$GANDI_API_KEY'
	option ip_source 'network'
	option ip_network 'wan2'
	option interface 'wan2'
	option use_syslog '2'
	option check_unit 'minutes'
	option force_unit 'minutes'
	option retry_unit 'seconds'
EOF
uci commit ddns

echo "DynDNS settings done."


# Set up Wireguard
GLOBAL_IPV6_PREFIX=$(ip -6 a show dev eth0.2 scope global | grep -o -E ' \w+:\w+:\w+:\w+:')
echo "Global IPv6 prefix: ${GLOBAL_IPV6_PREFIX}"

opkg install luci-proto-wireguard luci-app-wireguard qrencode

cat << EOF > /etc/init.d/wg_proxy
#!/bin/sh /etc/rc.common
START=94
start() {
until test -e /sys/class/net/eth0.2 ; do sleep 1; done
until test -e /sys/class/net/br-lan ; do sleep 1; done
logger -p daemon.info -t wg_proxy 'Setting up WireGuard NDP proxy.'
EOF
chmod 0755 /etc/init.d/wg_proxy

# wg_lan is trusted wireguard interface
uci set network.wg_lan=interface
uci set network.wg_lan.proto='wireguard'
uci set network.wg_lan.private_key="$WG_KEY"
uci set network.wg_lan.listen_port='51820'
uci set network.wg_lan.addresses="10.0.99.1/24 ${GLOBAL_IPV6_PREFIX}:9999:1/112"
echo "ip -6 neigh add proxy ${GLOBAL_IPV6_PREFIX}:9999:1 dev eth0.2" >> /etc/init.d/wg_proxy
echo "ip -6 neigh add proxy ${GLOBAL_IPV6_PREFIX}:9999:1 dev br-lan" >> /etc/init.d/wg_proxy

# wg_dmz is untrusted wireguard interface
uci set network.wg_dmz=interface
uci set network.wg_dmz.proto='wireguard'
uci set network.wg_dmz.private_key="$WG_KEY"
uci set network.wg_dmz.listen_port='51821'
uci set network.wg_dmz.addresses="10.0.66.1/24 ${GLOBAL_IPV6_PREFIX}:6666:1/112"
echo "ip -6 neigh add proxy ${GLOBAL_IPV6_PREFIX}:6666:1 dev eth0.2" >> /etc/init.d/wg_proxy
echo "ip -6 neigh add proxy ${GLOBAL_IPV6_PREFIX}:6666:1 dev br-lan" >> /etc/init.d/wg_proxy

function create_lan_peer () {
	uci set network.$1=wireguard_wg_lan
	uci set network.$1.description="$1"
	uci set network.$1.public_key=$2
	uci set network.$1.preshared_key="$WG_PRESHARED_KEY"
	uci set network.$1.allowed_ips="10.0.99.$3/32 ${GLOBAL_IPV6_PREFIX}:9999:$3/128"
	uci set network.$1.route_allowed_ips='1'
	uci set network.$1.persistent_keepalive='25'
	echo "ip -6 neigh add proxy ${GLOBAL_IPV6_PREFIX}:9999:$3 dev eth0.2" >> /etc/init.d/wg_proxy
	echo "ip -6 neigh add proxy ${GLOBAL_IPV6_PREFIX}:9999:$3 dev br-lan" >> /etc/init.d/wg_proxy
}

function create_dmz_peer () {
	uci set network.$1=wireguard_wg_dmz
	uci set network.$1.description="$1"
	uci set network.$1.public_key=$2
	uci set network.$1.preshared_key="$WG_PRESHARED_KEY"
	uci set network.$1.allowed_ips="10.0.66.$3/32 ${GLOBAL_IPV6_PREFIX}:6666:$3/128"
	uci set network.$1.route_allowed_ips='1'
	uci set network.$1.persistent_keepalive='25'
	echo "ip -6 neigh add proxy ${GLOBAL_IPV6_PREFIX}:6666:$3 dev eth0.2" >> /etc/init.d/wg_proxy
	echo "ip -6 neigh add proxy ${GLOBAL_IPV6_PREFIX}:6666:$3 dev br-lan" >> /etc/init.d/wg_proxy
}

create_lan_peer torii 'QSWgw0YVspOkueVsLNBc/UPIhZq6ZfbNw/0EMXZmMGI=' 3
create_lan_peer bae 'is4/cpRQYOogqZ5wwulRxwaHygDobsZT0jlCyHnF6D4=' 10

echo "logger -p daemon.info -t wg_proxy 'WireGuard NDP proxy succesfully set up.'" >> /etc/init.d/wg_proxy
echo "}" >> /etc/init.d/wg_proxy
/etc/init.d/wg_proxy enable

uci commit network

# Allow Wireguard ports
uci set firewall.allow_wireguard=rule
uci set firewall.allow_wireguard.name='Input Wireguard'
uci set firewall.allow_wireguard.proto='udp'
uci set firewall.allow_wireguard.src='wan'
uci set firewall.allow_wireguard.dest_port='51820 51821'
uci set firewall.allow_wireguard.target='ACCEPT'

# Add wg_lan as part of LAN zone
uci set firewall.cfg02dc81.network='lan wg_lan'

# Create a DMZ zone for wg_dmz
uci set firewall.dmz=zone
uci set firewall.dmz.name='dmz'
uci set firewall.dmz.input='REJECT'
uci set firewall.dmz.output='ACCEPT'
uci set firewall.dmz.forward='REJECT'
uci set firewall.dmz.network='wg_dmz'

uci set firewall.lan2dmz=forwarding
uci set firewall.lan2dmz.src='lan'
uci set firewall.lan2dmz.dest='dmz'

uci set firewall.dmz2wan=forwarding
uci set firewall.dmz2wan.src='dmz'
uci set firewall.dmz2wan.dest='wan'

uci set firewall.input_dns_dmz=rule
uci set firewall.input_dns_dmz.name='Input DNS from DMZ'
uci set firewall.input_dns_dmz.src='dmz'
uci set firewall.input_dns_dmz.dest_port='53'
uci set firewall.input_dns_dmz.target='ACCEPT'

uci set firewall.input_icmp_dmz=rule
uci set firewall.input_icmp_dmz.name='Input ICMP from DMZ'
uci set firewall.input_icmp_dmz.src='dmz'
uci set firewall.input_icmp_dmz.proto='icmp'
uci set firewall.input_icmp_dmz.target='ACCEPT'

uci set firewall.forward_common_dmz=rule
uci set firewall.forward_common_dmz.name='Forward HTTP(S) & SSH from DMZ'
uci set firewall.forward_common_dmz.src='dmz'
uci set firewall.forward_common_dmz.dest='*'
uci set firewall.forward_common_dmz.dest_port='22 80 443'
uci set firewall.forward_common_dmz.target='ACCEPT'

uci set firewall.forward_icmp_dmz=rule
uci set firewall.forward_icmp_dmz.name='Forward ICMP from DMZ'
uci set firewall.forward_icmp_dmz.src='dmz'
uci set firewall.forward_icmp_dmz.dest='*'
uci set firewall.forward_icmp_dmz.proto='icmp'
uci set firewall.forward_icmp_dmz.target='ACCEPT'

uci commit firewall

# Allow Dnsmasq to respond to queries from Wireguard tunnel
uci set dhcp.cfg01411c.localservice='0'
uci commit dhcp

# Enable proxying NDP messages between external interfaces and WG interfaces
# (Without this 'ip -6 neigh add proxy' doesn't work)
echo "net.ipv6.conf.all.proxy_ndp = 1" > /etc/sysctl.conf

echo "Wireguard settings done."

# MWAN3 Multi-WAN load balancer
# NOTE: the ORDER of the traffic rules is important, they are processed in top-down order

opkg install mwan3 luci-app-mwan3
uci import mwan3 << EOF
config globals 'globals'
	option mmx_mask '0x3F00'

config interface 'wan'
	option enabled '1'
	list track_ip '8.8.4.4'
	list track_ip '8.8.8.8'
	list track_ip '208.67.222.222'
	list track_ip '208.67.220.220'
	option reliability '2'
	option family 'ipv4'

config interface 'wan2'
	option enabled '1'
	list track_ip '8.8.4.4'
	list track_ip '8.8.8.8'
	list track_ip '208.67.222.222'
	list track_ip '208.67.220.220'
	option reliability '2'
	option family 'ipv4'

config member 'wan_w1'
	option interface 'wan'
	option metric '1'
	option weight '1'

config member 'wan2_w5'
	option interface 'wan2'
	option metric '1'
	option weight '5'

config policy 'wan_only'
	list use_member 'wan_w1'

config policy 'wan2_only'
	list use_member 'wan2_w5'

config policy 'balanced'
	list use_member 'wan_w1'
	list use_member 'wan2_w5'

config rule 'https'
	option sticky '1'
	option dest_port '443'
	option proto 'tcp'
	option use_policy 'balanced'
	option family 'ipv4'

config rule 'wan_dns'
	option dest_ip '210.147.235.3,133.205.66.51'
	option family 'ipv4'
	option use_policy 'wan_only'

config rule 'wan2_dns'
	option dest_ip '203.165.31.152,122.197.254.136'
	option family 'ipv4'
	option use_policy 'wan2_only'

config rule 'default_rule'
	option dest_ip '0.0.0.0/0'
	option family 'ipv4'
	option use_policy 'balanced'
EOF


# Remove leases that were made before the static DHCP settings
rm -f /tmp/dhcp.leases
