#!/bin/sh -eu

GANDI_API_KEY=${1:?}
WG_KEY=${2:?}
WG_PRESHARED_KEY=${3:?}

. /etc/openwrt_release

echo "Setting up config on TP-Link Archer C7 v2.0/JP. OS: $DISTRIB_DESCRIPTION"

echo "Start installing external packages."

opkg update

echo "Updated packet list."

# Some packages seem to cause problems when installed together, so let's upgrade them one-by-one
opkg upgrade dnsmasq
sleep 5
opkg upgrade opkg
sleep 5
opkg upgrade wpad-basic
sleep 5

PACKAGES=$(opkg list-upgradable | cut -f 1 -d ' ')

if [ -n "$PACKAGES" ]; then
	echo "Packages to upgrade: $(echo $PACKAGES | tr '\n' ' ')"
	mkdir -p packages
	cd packages

	# We download the packages first because "opkg upgrade dnsmasq" seems to disable
	# dnsmasq BEFORE downloading the upgrades, which makes the downloads fail
	echo "$PACKAGES" | xargs opkg download
	echo "Packages downloaded:"
	ls -lah *.ipk

	# Install the rest
	opkg install *.ipk
	# The luci config file conflicts with the new package
	# Resolve conflict with an upgraded config file
	mv /etc/config/luci-opkg /etc/config/luci || true
	reload_config
	cd ..
	rm -rf packages
fi

echo "Base packages upgraded"


opkg install curl nano coreutils-base64 wget bind-dig tcpdump ip-full diffutils

echo "Utilities installed."


# Install nginx to support performant HTTPS admin panel
opkg install luci-ssl-nginx

# Use our own certificate
sed -i -e 's|/etc/nginx/nginx.cer|/etc/ssl/mon.lan.chain.pem|' -e 's|/etc/nginx/nginx.key|/etc/ssl/mon.lan.key|' /etc/nginx/nginx.conf

/etc/init.d/nginx restart

echo "HTTPS enabled on web interface."


# Set up WPS
# It doesn't seem to work with two radios, so setting up only the 2.5Ghz one.
opkg remove wpad-basic
opkg install wpad hostapd-utils

uci set wireless.default_radio1.wps_pushbutton='1'
uci commit wireless

cat << EOF > /root/wps.sh
#!/bin/sh
hostapd_cli -i wlan1 wps_pbc
hostapd_cli -i wlan1 wps_get_status
EOF
chmod 0755 /root/wps.sh

echo "WPS settings done."


# Set up dynamic DNS (Gandi)
# Gandi is not supported in 19.07, so downloading the trunk packages:
echo "src/gz openwrt_snapshot_packages http://downloads.openwrt.org/snapshots/packages/mips_24kc/packages" >> /etc/opkg/customfeeds.conf
echo "src/gz openwrt_snapshot_luci http://downloads.openwrt.org/snapshots/packages/mips_24kc/luci/" >> /etc/opkg/customfeeds.conf
opkg update
opkg install luci-app-ddns ddns-scripts-gandi
echo "" > /etc/opkg/customfeeds.conf
opkg update

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

create_lan_peer bae 'is4/cpRQYOogqZ5wwulRxwaHygDobsZT0jlCyHnF6D4=' 10
create_lan_peer opl 'DcOeAkCLza1RmDz722u0kQfi+U64hA4UxJMQc6BAChU=' 20
create_dmz_peer bae_dmz 'QTGbWzt70RrG+2ymLMqaPwSx4OxsL1IP3yhOTxQ8JCs=' 10
create_dmz_peer opl_dmz 'QhsUPBja4sl8QVe66R0/LnR/WtxqfRn2oj4/NTWFjEc=' 20

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


echo "Rebooting."
reboot now
