#!/bin/sh
# Print the GUA of a LAN host whose host id comes from a static DHCPv6 lease
# (cafe's, see the `config host` entry in /etc/config/dhcp). The /64 comes from
# the delegation and the host id does not change, so only the network part
# moves. Used as ddns-scripts' ip_script, which passes the host id as $1:
#
#     lan_suffix.sh cafe  ->  2405:1200:54e:a100::cafe

suffix="$1"
[ -n "$suffix" ] || exit 1

# The LAN has two assigned prefixes: the static ULA and the first /64 of the
# delegation. Only the second is routable, and netifd reports both, so pick the
# one that is not the ULA rather than relying on the order.
#
# Before the DHCPv6 REPLY arrives there is only the ULA, so this prints nothing
# and fails. ddns-scripts then leaves the record it has: a stale address is
# better than a private one, and the next run picks up the delegation.
ula=$(uci -q get network.globals.ula_prefix | sed 's|::/[0-9]*$||')
[ -n "$ula" ] || exit 1
stem=$(ubus call network.interface.lan status 2>/dev/null |
	jsonfilter -e '@["ipv6-prefix-assignment"][*].address' 2>/dev/null |
	grep -v "^${ula}" | head -n 1 | sed 's/:*$//')
[ -n "$stem" ] || exit 1

printf '%s::%s\n' "$stem" "$suffix"
