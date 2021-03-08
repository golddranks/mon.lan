#!/bin/sh -eu

GANDI_API_KEY=${1:?}
WG_KEY=${2:?}
WG_PRESHARED_KEY=${3:?}

. /etc/openwrt_release

echo "Setting up config on TP-Link Archer C7 v2.0/JP. OS: $DISTRIB_DESCRIPTION"

echo "Start installing external packages."

opkg update

echo "Updated packet list."

PACKAGES=$(opkg list-upgradable | cut -f 1 -d ' ')

if [ -n "$PACKAGES" ]; then
	echo "Packages to upgrade: $(echo $PACKAGES | tr '\n' ' ')"
	mkdir packages
	cd packages
	# We download the packages first because "opkg upgrade dnsmasq" seems to disable
	# dnsmasq BEFORE downloading the upgrades, which makes the downloads fail
	echo "$PACKAGES" | xargs opkg download
	echo "Packages downloaded:"
	ls -lah *.ipk
	opkg install *.ipk
	# The luci config file conflicts with the new package
	# Resolve conflict with an upgraded config file
	mv /etc/config/luci-opkg /etc/config/luci || true
	# We'll ignore upgrading the DHCP settings file because we already changed it
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

opkg install luci-proto-wireguard luci-app-wireguard

cat << EOF > /etc/init.d/wg_proxy
#!/bin/sh /etc/rc.common
START=94
start() {
until test -e /sys/class/net/eth0.2 ; do sleep 1; done
until test -e /sys/class/net/br-lan ; do sleep 1; done
echo "Setting up WireGuard NDP proxy."
EOF
chmod 0755 /etc/init.d/wg_proxy

# wg0 is trusted LAN wireguard IF
uci set network.wg0=interface
uci set network.wg0.proto='wireguard'
uci set network.wg0.private_key="$WG_KEY"
uci set network.wg0.listen_port='51820'
uci set network.wg0.addresses="10.0.99.1/24 ${GLOBAL_IPV6_PREFIX}:9999:1/112"
echo "ip -6 neigh add proxy ${GLOBAL_IPV6_PREFIX}::9999:1 dev eth0.2" /etc/init.d/wg_proxy
echo "ip -6 neigh add proxy ${GLOBAL_IPV6_PREFIX}::9999:1 dev br-lan" /etc/init.d/wg_proxy

# wg1 is untrusted DMZ wireguard IF
uci set network.wg1=interface
uci set network.wg1.proto='wireguard'
uci set network.wg1.private_key="$WG_KEY"
uci set network.wg1.listen_port='51821'
uci set network.wg1.addresses="10.0.66.1/24 ${GLOBAL_IPV6_PREFIX}:6666:1/112"
echo "ip -6 neigh add proxy ${GLOBAL_IPV6_PREFIX}::6666:1 dev eth0.2" /etc/init.d/wg_proxy
echo "ip -6 neigh add proxy ${GLOBAL_IPV6_PREFIX}::6666:1 dev br-lan" /etc/init.d/wg_proxy

uci set network.bae=wireguard_wg0
uci set network.bae.description='bae'
uci set network.bae.public_key='is4/cpRQYOogqZ5wwulRxwaHygDobsZT0jlCyHnF6D4='
uci set network.bae.preshared_key="$WG_PRESHARED_KEY"
uci set network.bae.allowed_ips="10.0.99.10/32 ${GLOBAL_IPV6_PREFIX}:9999:10/128"
uci set network.bae.route_allowed_ips='1'
uci set network.bae.persistent_keepalive='25'
echo "ip -6 neigh add proxy ${GLOBAL_IPV6_PREFIX}::9999:10 dev eth0.2" >> /etc/init.d/wg_proxy
echo "ip -6 neigh add proxy ${GLOBAL_IPV6_PREFIX}::9999:10 dev br-lan" >> /etc/init.d/wg_proxy

uci set network.one_plus=wireguard_wg0
uci set network.one_plus.description='one_plus'
uci set network.one_plus.public_key='DcOeAkCLza1RmDz722u0kQfi+U64hA4UxJMQc6BAChU='
uci set network.one_plus.preshared_key="$WG_PRESHARED_KEY"
uci set network.one_plus.allowed_ips="10.0.99.20/32 ${GLOBAL_IPV6_PREFIX}:9999:20/128"
uci set network.one_plus.route_allowed_ips='1'
uci set network.one_plus.persistent_keepalive='25'
echo "ip -6 neigh add proxy ${GLOBAL_IPV6_PREFIX}::9999:20 dev eth0.2" >> /etc/init.d/wg_proxy
echo "ip -6 neigh add proxy ${GLOBAL_IPV6_PREFIX}::9999:20 dev br-lan" >> /etc/init.d/wg_proxy

uci set network.bae_dmz=wireguard_wg1
uci set network.bae_dmz.description='bae dmz'
uci set network.bae_dmz.public_key='is4/cpRQYOogqZ5wwulRxwaHygDobsZT0jlCyHnF6D4='
uci set network.bae_dmz.preshared_key="$WG_PRESHARED_KEY"
uci set network.bae_dmz.allowed_ips="10.0.66.10/32 ${GLOBAL_IPV6_PREFIX}:6666:10/128"
uci set network.bae_dmz.route_allowed_ips='1'
uci set network.bae_dmz.persistent_keepalive='25'
echo "ip -6 neigh add proxy ${GLOBAL_IPV6_PREFIX}::6666:10 dev eth0.2" >> /etc/init.d/wg_proxy
echo "ip -6 neigh add proxy ${GLOBAL_IPV6_PREFIX}::6666:10 dev br-lan" >> /etc/init.d/wg_proxy

echo "echo 'WireGuard NDP proxy set up.'" >> /etc/init.d/wg_proxy
echo "}" >> /etc/init.d/wg_proxy
/etc/init.d/wg_proxy enable

uci commit network

# Add wg0 as part of LAN zone
uci set firewall.cfg02dc81.network='lan wg0'

# Add wg1 as part of WAN zone
uci set firewall.cfg03dc81.network='wan wan6 wg1'

# Add Allow-Wireguard LAN (trusted) port hole to firewall
uci set firewall.allow_wireguard_lan=rule
uci set firewall.allow_wireguard_lan.name='Allow-Wireguard LAN'
uci set firewall.allow_wireguard_lan.proto='udp'
uci set firewall.allow_wireguard_lan.src='wan'
uci set firewall.allow_wireguard_lan.dest_port='51820'
uci set firewall.allow_wireguard_lan.target='ACCEPT'

# Add Allow-Wireguard DMZ (untrusted) port hole to firewall
uci set firewall.allow_wireguard_dmz=rule
uci set firewall.allow_wireguard_dmz.name='Allow-Wireguard DMZ'
uci set firewall.allow_wireguard_dmz.proto='udp'
uci set firewall.allow_wireguard_dmz.src='wan'
uci set firewall.allow_wireguard_dmz.dest_port='51821'
uci set firewall.allow_wireguard_dmz.target='ACCEPT'
uci commit firewall

# Allow Dnsmasq to respond to queries from Wireguard tunnel
uci set dhcp.@dnsmasq[0].localservice='0'
uci commit dhcp

# Enable proxying NDP messages between external interfaces and WG interfaces
echo "net.ipv6.conf.all.proxy_ndp = 1" > /etc/sysctl.conf

echo "Wireguard settings done."


echo "Rebooting."
reboot now
