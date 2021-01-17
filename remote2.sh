#!/bin/sh -eu

GANDI_API_KEY=${1:?}
WG_KEY=${2:?}
WG_PRESHARED_KEY=${3:?}


echo "Setting up config on TP-Link Archer C7 v2.0/JP. OS: OpenWrt 19.07.5."

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

# MacOS NDP+RA supports only LLA source addresses, so don't use ULA
uci set network.globals.ula_prefix=''
uci commit network

# IPv6 tokenized interface identifier support
cat << EOF > /etc/init.d/ipv6_ra_tokenized
#!/bin/sh /etc/rc.common
START=94
start() {
until test -e /sys/class/net/eth0.2 ; do sleep 1; done
echo "Setting up RA+NDP-based IPv6 with tokenized host address."
sysctl -w net.ipv6.conf.eth0.2.accept_ra=2
ip token set '::1' dev eth0.2
}
EOF
chmod 0755 /etc/init.d/ipv6_ra_tokenized
/etc/init.d/ipv6_ra_tokenized enable

echo "IPv6 settings done."


uci set dhcp.nagi=host
uci set dhcp.nagi.name='nagi'
uci set dhcp.nagi.mac='A8:A1:59:36:BE:32'
uci set dhcp.nagi.ip='10.0.0.10'
uci set dhcp.nagi.hostid='10'
uci set dhcp.nagi.dns='1'

uci set dhcp.poi=host
uci set dhcp.poi.name='poi'
uci set dhcp.poi.mac='DC:A6:32:08:DB:FC'
uci set dhcp.poi.ip='10.0.0.20'
uci set dhcp.poi.hostid='20'
uci set dhcp.poi.dns='1'
uci commit dhcp

echo "DHCP static lease settings done."


uci set firewall.ssh_redirect=redirect
uci set firewall.ssh_redirect.target='DNAT'
uci set firewall.ssh_redirect.name='SSH'
uci set firewall.ssh_redirect.src='wan'
uci set firewall.ssh_redirect.src_dport='22'
uci set firewall.ssh_redirect.dest_ip='10.0.0.20'
uci set firewall.ssh_redirect.dest_port='22'
uci commit firewall

echo "Port forwarding settings done."


reload_config
echo "Wait for network && DNS before accessing package repo."
ubus -t 30 wait_for network.interface.wan
ubus -t 30 wait_for dnsmasq


echo "Start installing external packages."

opkg update
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
	option ip_source 'network'
	option ip_network 'wan6'
	option interface 'wan6'
	option use_syslog '2'
	option check_unit 'minutes'
	option force_unit 'minutes'
	option retry_unit 'seconds'
EOF
uci commit ddns

echo "DynDNS settings done."


# The luci config file conflicts with the new package
opkg list-upgradable | cut -f 1 -d ' ' | xargs --no-run-if-empty opkg upgrade
# Resolve conflict with an upgraded config file
mv /etc/config/luci-opkg /etc/config/luci || true

echo "Base packages upgraded"


opkg install curl nano coreutils-base64 wget bind-dig tcpdump ip-full

echo "utilities installed."


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
reload_config


reload_config
# Remove leases that were made before the static settings
rm -f /tmp/dhcp.leases


echo "Rebooting."
reboot now
