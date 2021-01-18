#!/bin/sh -eu

GANDI_API_KEY=${1:?}
WG_KEY=${2:?}
WG_PRESHARED_KEY=${3:?}


echo "Setting up config on TP-Link Archer C7 v2.0/JP. OS: OpenWrt 19.07.5."

echo "Start installing external packages."

opkg update

# The luci config file conflicts with the new package
opkg list-upgradable | cut -f 1 -d ' ' | xargs --no-run-if-empty opkg upgrade
# Resolve conflict with an upgraded config file
mv /etc/config/luci-opkg /etc/config/luci || true

echo "Base packages upgraded"


opkg install curl nano coreutils-base64 wget bind-dig tcpdump ip-full diffutils

echo "utilities installed."


opkg install luci-ssl-nginx

sed -i -e 's|/etc/nginx/nginx.cer|/etc/ssl/mon.lan.chain.pem|' -e 's|/etc/nginx/nginx.key|/etc/ssl/mon.lan.key|' /etc/nginx/nginx.conf

/etc/init.d/nginx reload

echo "HTTPS enabled on web interface."

# It doesn't seem to work with two radios, so setting up only the 2.5Ghz one.
uci set wireless.default_radio1.wps_pushbutton='1'
uci commit wireless

opkg remove wpad-basic
opkg install wpad hostapd-utils

cat << EOF > /root/wps.sh
#!/bin/sh
hostapd_cli -i wlan1 wps_pbc
hostapd_cli -i wlan1 wps_get_status
EOF
chmod 0755 /root/wps.sh

echo "WPS settings done."


opkg install http://downloads.openwrt.org/snapshots/packages/mips_24kc/packages/ddns-scripts-services_2.8.2-4_all.ipk
opkg install http://downloads.openwrt.org/snapshots/packages/mips_24kc/packages/ddns-scripts_2.8.2-4_all.ipk
opkg install http://downloads.openwrt.org/snapshots/packages/mips_24kc/packages/ddns-scripts-gandi_2.8.2-4_all.ipk
opkg install http://downloads.openwrt.org/snapshots/packages/mips_24kc/luci/luci-app-ddns_git-20.356.70818-05328b2_all.ipk

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
	option ip_source 'interface'
	option ip_interface 'eth0.2'
	option interface 'eth0.2'
	option use_syslog '2'
	option check_unit 'minutes'
	option force_unit 'minutes'
	option retry_unit 'seconds'
EOF
uci commit ddns

echo "DynDNS settings done."


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

uci set network.wg0=interface
uci set network.wg0.proto='wireguard'
uci set network.wg0.private_key="$WG_KEY"
uci set network.wg0.listen_port='51820'
uci set network.wg0.addresses="10.0.99.1/24 ${GLOBAL_IPV6_PREFIX}:9999:1/112"
echo "ip -6 neigh add proxy ${GLOBAL_IPV6_PREFIX}::9999:1 dev eth0.2" /etc/init.d/wg_proxy
echo "ip -6 neigh add proxy ${GLOBAL_IPV6_PREFIX}::9999:1 dev br-lan" /etc/init.d/wg_proxy

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

echo "echo 'WireGuard NDP proxy set up.'" >> /etc/init.d/wg_proxy
echo "}" >> /etc/init.d/wg_proxy
/etc/init.d/wg_proxy enable

uci commit network

# Add wg0 as part of LAN zone
uci set firewall.cfg02dc81.network='lan wg0'

# Add Allow-Wireguard port hole to firewall
uci set firewall.allow_wireguard=rule
uci set firewall.allow_wireguard.name='Allow-Wireguard'
uci set firewall.allow_wireguard.proto='udp'
uci set firewall.allow_wireguard.src='wan'
uci set firewall.allow_wireguard.dest_port='51820'
uci set firewall.allow_wireguard.target='ACCEPT'
uci commit firewall

# Allow Dnsmasq to respond to queries from Wireguard tunnel
uci set dhcp.@dnsmasq[0].localservice='0'
uci commit dhcp

# Enable proxying NDP messages between external interfaces and wg0
echo "net.ipv6.conf.all.proxy_ndp = 1" > /etc/sysctl.conf

echo "Wireguard settings done."


echo "Rebooting."
reboot now
