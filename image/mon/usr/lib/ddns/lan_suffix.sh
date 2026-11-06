#!/bin/sh
# Print the GUA of a LAN host whose host id is pinned by a static DHCPv6
# lease (cafe's, see the `config host` entry in /etc/config/dhcp). The
# delegated /64 changes with the PD; the host id does not. Used as
# ddns-scripts' ip_script, so it takes the host id as $1:
#
#     lan_suffix.sh cafe  ->  2405:1200:<delegated /64>:cafe

suffix="$1"
[ -n "$suffix" ] || exit 1

# A churning PD leaves stale GUAs on br-lan, so prefer the one inside the
# current delegation; DDNS must publish the address that is actually routed.
#
# When the LAN is pinned to a prefix the delegation does not cover - the runtime
# workaround for J:COM not routing fresh delegations - nothing matches and the
# first GUA wins. That is the pinned one only because /etc/config/network lists
# it first, so the order there matters as long as the pin exists.
pd_stem=$(ubus call network.interface.wan6 status 2>/dev/null |
	jsonfilter -e '@["ipv6-prefix"][0].address' 2>/dev/null | sed 's/::$//')
guas=$(ip -6 addr show dev br-lan scope global |
	awk '/inet6 [23]/ { split($2, a, "/"); print a[1] }')
addr=
for g in $guas; do
	[ -n "$pd_stem" ] &&
		[ "$(printf '%s' "$g" | cut -d: -f1-4)" = "$pd_stem" ] &&
		addr=$g && break
done
[ -n "$addr" ] || addr=$(printf '%s\n' "$guas" | head -n 1)
[ -n "$addr" ] || exit 1

printf '%s\n' "$addr" |
	awk -F: -v s="$suffix" '{ printf "%s:%s:%s:%s::%s\n", $1, $2, $3, $4, s }'
