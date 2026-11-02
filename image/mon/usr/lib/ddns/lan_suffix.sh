#!/bin/sh
# Print the GUA of a LAN host whose host id is pinned by a static DHCPv6
# lease (cafe's, see the `config host` entry in /etc/config/dhcp). The
# delegated /64 changes with the PD; the host id does not. Used as
# ddns-scripts' ip_script, so it takes the host id as $1:
#
#     lan_suffix.sh cafe  ->  2405:1200:542:5f00::cafe

suffix="$1"
[ -n "$suffix" ] || exit 1

addr=$(ip -6 addr show dev br-lan scope global |
	awk '/inet6 [23]/ { split($2, a, "/"); print a[1]; exit }')
[ -n "$addr" ] || exit 1

printf '%s\n' "$addr" |
	awk -F: -v s="$suffix" '{ printf "%s:%s:%s:%s::%s\n", $1, $2, $3, $4, s }'
