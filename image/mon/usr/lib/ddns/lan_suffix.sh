#!/bin/sh
# Print the GUA of a LAN host with a fixed SLAAC suffix (`slaac token` in
# dhcpcd), e.g. mame's ::10. The delegated /64 changes with the PD; the suffix
# does not. Used as ddns-scripts' ip_script, so it takes the suffix as $1:
#
#     lan_suffix.sh 10  ->  2405:1200:542:5500::10

suffix="$1"
[ -n "$suffix" ] || exit 1

addr=$(ip -6 addr show dev br-lan scope global |
	awk '/inet6 [23]/ { split($2, a, "/"); print a[1]; exit }')
[ -n "$addr" ] || exit 1

printf '%s\n' "$addr" |
	awk -F: -v s="$suffix" '{ printf "%s:%s:%s:%s::%s\n", $1, $2, $3, $4, s }'
