#!/bin/sh -eu

. "${0%/*}/utils.sh"

WG_KEY=${1:?}
WG_PRESHARED_KEY=${2:?}
WG_LAN_PEERS=${3:?}
WG_DMZ_PEERS=${4:?}

# Set up Wireguard
GLOBAL_IPV6_PREFIX=$(get_global_ipv6_prefix)
echo "Global IPv6 prefix: ${GLOBAL_IPV6_PREFIX}"

update_opkg
opkg install luci-proto-wireguard luci-app-wireguard qrencode

NEIGH_PROXY_CMDS=$(mktemp)

# wg_lan is trusted wireguard interface
uci set network.wg_lan=interface
uci set network.wg_lan.proto='wireguard'
uci set network.wg_lan.private_key="$WG_KEY"
uci set network.wg_lan.listen_port='51820'
uci set network.wg_lan.addresses="10.0.99.1/24 ${GLOBAL_IPV6_PREFIX}::9999:1/112"
echo "ip -6 neigh add proxy ${GLOBAL_IPV6_PREFIX}::9999:1 dev eth0.2" >> "$NEIGH_PROXY_CMDS"
echo "ip -6 neigh add proxy ${GLOBAL_IPV6_PREFIX}::9999:1 dev br-lan" >> "$NEIGH_PROXY_CMDS"

echo "$WG_LAN_PEERS" | while read -r NAME PRIVKEY PUBKEY NUM; do
	echo "Adding LAN peer $NAME"
	uci set "network.$NAME=wireguard_wg_lan"
	uci set "network.$NAME.description=$NAME"
	uci set "network.$NAME.public_key=$PUBKEY"
	uci set "network.$NAME.private_key=$PRIVKEY"
	uci set "network.$NAME.preshared_key=$WG_PRESHARED_KEY"
	uci set "network.$NAME.allowed_ips=10.0.99.$NUM/32 ${GLOBAL_IPV6_PREFIX}::9999:$NUM/128"
	uci set "network.$NAME.route_allowed_ips=1"
	uci set "network.$NAME.persistent_keepalive=25"
	echo "ip -6 neigh add proxy ${GLOBAL_IPV6_PREFIX}::9999:$NUM dev eth0.2" >> "$NEIGH_PROXY_CMDS"
	echo "ip -6 neigh add proxy ${GLOBAL_IPV6_PREFIX}::9999:$NUM dev br-lan" >> "$NEIGH_PROXY_CMDS"
done

# wg_dmz is untrusted wireguard interface
uci set network.wg_dmz=interface
uci set network.wg_dmz.proto='wireguard'
uci set network.wg_dmz.private_key="$WG_KEY"
uci set network.wg_dmz.listen_port='51821'
uci set network.wg_dmz.addresses="10.0.66.1/24 ${GLOBAL_IPV6_PREFIX}::6666:1/112"
echo "ip -6 neigh add proxy ${GLOBAL_IPV6_PREFIX}::6666:1 dev eth0.2" >> "$NEIGH_PROXY_CMDS"
echo "ip -6 neigh add proxy ${GLOBAL_IPV6_PREFIX}::6666:1 dev br-lan" >> "$NEIGH_PROXY_CMDS"

echo "$WG_DMZ_PEERS" | while read -r NAME PRIVKEY PUBKEY NUM; do
	echo "Adding DMZ peer $NAME"
	uci set "network.$NAME=wireguard_wg_dmz"
	uci set "network.$NAME.description=$NAME"
	uci set "network.$NAME.public_key=$PUBKEY"
	uci set "network.$NAME.private_key=$PRIVKEY"
	uci set "network.$NAME.preshared_key=$WG_PRESHARED_KEY"
	uci set "network.$NAME.allowed_ips=10.0.66.$NUM/32 ${GLOBAL_IPV6_PREFIX}::6666:$NUM/128"
	uci set "network.$NAME.route_allowed_ips=1"
	uci set "network.$NAME.persistent_keepalive=25"
	echo "ip -6 neigh add proxy ${GLOBAL_IPV6_PREFIX}::6666:$NUM dev eth0.2" >> "$NEIGH_PROXY_CMDS"
	echo "ip -6 neigh add proxy ${GLOBAL_IPV6_PREFIX}::6666:$NUM dev br-lan" >> "$NEIGH_PROXY_CMDS"
done

cat << EOF > /etc/init.d/wg_proxy
#!/bin/sh /etc/rc.common
START=94
start() {
	until test -e /sys/class/net/eth0.2 ; do sleep 1; done
	until test -e /sys/class/net/br-lan ; do sleep 1; done
	logger -p daemon.info -t wg_proxy 'Setting up WireGuard NDP proxy.'
$(cat "$NEIGH_PROXY_CMDS")
	logger -p daemon.info -t wg_proxy 'WireGuard NDP proxy succesfully set up.'
	logger -p daemon.info -t wg_proxy "\$(ip -6 neigh show proxy)"
}
EOF
chmod 0755 /etc/init.d/wg_proxy
rm "$NEIGH_PROXY_CMDS"
/etc/init.d/wg_proxy enable
/etc/init.d/wg_proxy restart

uci commit network

# Allow Wireguard ports
uci set firewall.allow_wireguard=rule
uci set firewall.allow_wireguard.name='Input Wireguard'
uci set firewall.allow_wireguard.proto='udp'
uci set firewall.allow_wireguard.src='wan'
uci set firewall.allow_wireguard.dest_port='51820 51821'
uci set firewall.allow_wireguard.target='ACCEPT'

# Add wg_lan as part of LAN zone
uci set firewall.lan_zone.network='lan wg_lan'

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
rename_uci_key dhcp cfg01411c dnsmasq
uci set dhcp.dnsmasq.localservice='0'
uci commit dhcp

# Enable proxying NDP messages between external interfaces and WG interfaces
# (Without this 'ip -6 neigh add proxy' doesn't work)
echo "net.ipv6.conf.all.proxy_ndp = 1" > /etc/sysctl.conf

echo "Wireguard settings done."
