#!/bin/sh -eu

. "${0%/*}/utils.sh"

GANDI_API_KEY=${1:?}

# Set up dynamic DNS (Gandi)
update_opkg
opkg install luci-app-ddns ddns-scripts-gandi

# TODO: remove this after updating to OpenWRT 23.05 (it contains this update)
curl https://raw.githubusercontent.com/golddranks/openwrt_packages/cefe85250ccfd7e3c9872d714e913ca2162ccbf4/net/ddns-scripts/files/usr/lib/ddns/update_gandi_net.sh > /usr/lib/ddns/update_gandi_net.sh

# Remove placeholder settings
delete_uci_key ddns.myddns_ipv4
delete_uci_key ddns.myddns_ipv6

DDNS_COMMON="option enabled 1
	option service_name 'gandi.net'
	option password '$GANDI_API_KEY'
	option use_syslog '2'
	option check_unit 'minutes'
	option force_unit 'minutes'
	option retry_unit 'seconds'
"

DDNS_IPV4="option use_ipv6 0
	option ip_source 'network'
	option ip_network 'wan_bg'
	option interface 'wan_bg'
	$DDNS_COMMON
"

uci -m import ddns << EOF
config service 'drasa_eu_ipv4'
	option lookup_host 'drasa.eu'
	option domain 'drasa.eu'
	option username '@'
	$DDNS_IPV4

config service 'bitwarden_ipv4'
	option lookup_host 'bitwarden.drasa.eu'
	option domain 'drasa.eu'
	option username 'bitwarden'
	$DDNS_IPV4

config service 'syncthing_ipv4'
	option lookup_host 'syncthing.drasa.eu'
	option domain 'drasa.eu'
	option username 'syncthing'
	$DDNS_IPV4

config service 'webshare_ipv4'
	option lookup_host 'webshare.drasa.eu'
	option domain 'drasa.eu'
	option username 'webshare'
	$DDNS_IPV4

config service 'drasa_eu_ipv6'
	option lookup_host 'drasa.eu'
	option domain 'drasa.eu'
	option username '@'
	option use_ipv6 1
	option ip_source 'network'
	option ip_network 'wan_bg6'
	option interface 'wan_bg6'
	$DDNS_COMMON

config service 'drasa_eu_jcom'
	option lookup_host 'jcom.drasa.eu'
	option domain 'drasa.eu'
	option username 'jcom'
	option use_ipv6 0
	option ip_source 'interface'
	option ip_interface 'eth0.3'
	option interface 'wan_jc'
	$DDNS_COMMON
EOF
uci commit ddns

echo "DynDNS settings done."
