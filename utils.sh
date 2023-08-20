#!/bin/sh

### For local install script ###

scpp () {
    scp -P "${CURRENT_PORT}" "$@"
}

sshp () {
    ssh -p "${CURRENT_PORT}" "$@"
}

### For remote install scripts ###

# Idempotent UCI functions

delete_uci_key () {
	uci -q delete "$1" && echo "Deleted $1" || echo "$1 is already deleted; that's OK."
}

rename_uci_key () {
	{
		uci -q show "${1}.${3}" > /dev/null \
		&& echo "${1}.${3} already exists/is renamed; that's OK.";
	} || {
		uci -q rename "${1}.${2}=${3}" \
		&& echo "Renamed ${1}.${2}=${3}";
	}
}

# Update OPKG only if it's older than 30 minutes
update_opkg () {
	find /var/opkg-lists/openwrt_core -mmin -30 | read -r || opkg update
}

get_global_ipv6_prefix () {
	ip -6 a show dev eth0.2 scope global \
		| grep -o -E 'inet6 \w+:\w+:\w+:\w+' \
		| tail -c +7
}
