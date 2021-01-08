#!/bin/sh -eu

ROOT_PW=${1:?}
SSH_PUBKEY=${2:?}
PPP_ID=${3:?}
PPP_PW=${4:?}
WIFI_PW=${5:?}
GANDI_API_KEY=${6:?}
WG_KEY=${7:?}
WG_PRESHARED_KEY=${8:?}


echo "Setting up config on TP-Link Archer C7 v2.0/JP. OS: OpenWrt 19.07.5."

echo "$SSH_PUBKEY" > /etc/dropbear/authorized_keys

# For convenience, add nagi, bae & OnePlus regardless
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQD7vzA+j56GjMFydRotjaCopjJUYDpiNgMw6uTpt2x7LisjY+fZR4uHJlcGpT7ooUROJPTekDyINcdRmhPTc0wg/G4MpeWfUhU8AkjXYhSpgGkh8Q56X4Qh120MG3oSm/FTHjobKaALJHuigiylQc8/G0GHh8Lzh5W/K1c7LZ6/EGCIHwBbJcjAPGQXJtjPOs8b68AK9TnXUAT3DR2cOUOraDTgRQuav63kbz4l7DHKpWXSBwNsw8v2UbL9Yedd677/MNeckmwA4yXe6Sx/4rqufV+5Sin1PGIJsOXc5AiwowcYQNDflbJqaC9UZiTu0ZSLoOV+QUvd4HsDACTVg/lCUDpzmsKFMZzk2lnd4XsLetRBx8rN3HVECxU+nRM05CyAAdL1OYlRN1amiM8XQ6S+FoB16k41e3XTjrhgxu+1hWt+vvlB61QTrI+5xTG3ra555mOzf98MrAzG7A0QONuGOvHtNT49dC2GcgXzHn0N3ntYgOECrpVrXJ+CLHh/LSc= kon@nagi" >> /etc/dropbear/authorized_keys
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDrhFzEaTWS9G/T+rLdGpqcIHevzFMypO7HuVd9/qMiX6G64oveaYBjgRriNricAB+koxKP2Kga6lB5NUVyTaqVN96cVwA9EQJ6GJAi5qZElWVZ7sjODgjVcXdzXSWfztbBLntgxx3J9Ugofy2lb4edGXO7lHqTUI4pmxE6QdIESjVdEUljHsX8uSBOiNXvgQ/TyvStEPp0R8GrKI4fTb+SSQCPn/NYrWFip4OMkqwp98wqqzT5WHi1p0rFzwedyH3SIdic0PCszoSdgRNL9j5AwQ6oXJC0gp5i+8etzyIkCp12o0LBVyWUQaYvH9MujR40p6kZKboUnlXxJ25EWnT5 kon@bae" >> /etc/dropbear/authorized_keys
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDylsriWf/lTC35CoTlsxYsIqFCvKtZ/qAqydB2PooH29+S+mKh68gDSzyYbXiRVTOiptX2PDQAIscpLGBU0W58Y39fchq9SJYwhA2V+gnNlHsb8f3P/TeqZ6+oahGgD0mCgM348GM2i43epkO6pOS7ciWhd9KI13iLQndABBJD3Z43rYlL94h1S1GpeZVqP+cBxKmRNAsWefNTSZkFTtpG8Lt47G7QR4GjoamjRlJzGVomzsKmFluOf2lcpvxl6TpvJmowPpkOXaMsIIQH/tWtgmR42AnCl7rQXAGzRGwDc6MKvS8Xsd55mrSYqHDEslu6F9SuHU4ob7NMtACjKgVF OnePlusRSA" >> /etc/dropbear/authorized_keys

passwd << EOF
$ROOT_PW
$ROOT_PW
EOF

uci set dropbear.cfg014dd4.RootPasswordAuth='off'
uci set dropbear.cfg014dd4.PasswordAuth='off'
uci commit dropbear

echo "Security config done."


uci set network.wan.proto='pppoe'
uci set network.wan.username="$PPP_ID"
uci set network.wan.password="$PPP_PW"
uci commit network

uci set wireless.default_radio0.ssid='Skeletor 5Ghz'
uci set wireless.default_radio0.key="$WIFI_PW"
uci set wireless.default_radio0.encryption='psk2'
uci set wireless.radio0.disabled='0'
uci set wireless.default_radio1.ssid='Skeletor 2.5Ghz'
uci set wireless.default_radio1.key="$WIFI_PW"
uci set wireless.default_radio1.encryption='psk2'
uci set wireless.radio1.disabled='0'
uci commit wireless

uci set system.cfg01e48a.hostname='mon'
uci set system.cfg01e48a.timezone='JST-9'
uci set system.cfg01e48a.zonename='Asia/Tokyo'
uci commit system


echo "Basic network config done. Reload config."
reload_config


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

echo "IPv6 settings done."

uci set dhcp.nagi=host
uci set dhcp.nagi.name='nagi'
uci set dhcp.nagi.mac='A8:A1:59:36:BE:32'
uci set dhcp.nagi.ip='192.168.1.10'
uci set dhcp.nagi.hostid='10'
uci set dhcp.nagi.dns='1'

uci set dhcp.poi=host
uci set dhcp.poi.name='poi'
uci set dhcp.poi.mac='DC:A6:32:08:DB:FC'
uci set dhcp.poi.ip='192.168.1.11'
uci set dhcp.poi.hostid='11'
uci set dhcp.poi.dns='1'
uci commit dhcp

echo "DHCP static lease settings done."


uci set firewall.ssh_redirect=redirect
uci set firewall.ssh_redirect.target='DNAT'
uci set firewall.ssh_redirect.name='SSH'
uci set firewall.ssh_redirect.src='wan'
uci set firewall.ssh_redirect.src_dport='22'
uci set firewall.ssh_redirect.dest='lan'
uci set firewall.ssh_redirect.dest_ip='192.168.1.11'
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

sed -i -e 's|/etc/nginx/nginx.cer|/etc/ssl/mon.lan.crt|' -e 's|/etc/nginx/nginx.key|/etc/ssl/mon.lan.key|' /etc/nginx/nginx.conf

/etc/init.d/nginx reload

echo "HTTPS enabled on web interface."


uci set wireless.default_radio0.wps_pushbutton='1'
uci set wireless.default_radio1.wps_pushbutton='1'
uci commit wireless

opkg remove wpad-basic
opkg install wpad hostapd-utils

cat << EOF > /root/wps.sh
#!/bin/sh
hostapd_cli -i wlan0 wps_pbc
hostapd_cli -i wlan1 wps_pbc
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
config service 'poi_ganba_re_4'
	option lookup_host 'poi.ganba.re'
	option domain 'ganba.re'
	option username 'poi'
	option password '$GANDI_API_KEY'
	option interface 'wan'
	option ip_source 'network'
	option ip_network 'wan'
	option update_script '/usr/lib/ddns/update_gandi_net.sh'
	option dns_server 'ns-2-a.gandi.net'
	option enabled '1'

config service 'poi_ganba_re_6'
	option use_ipv6 '1'
	option lookup_host 'poi.ganba.re'
	option domain 'ganba.re'
	option username 'poi'
	option password '$GANDI_API_KEY'
	option interface 'wan6'
	option ip_source 'network'
	option ip_network 'wan6'
	option update_script '/usr/lib/ddns/update_gandi_net.sh'
	option dns_server 'ns-2-a.gandi.net'
	option enabled '1'
EOF
uci commit ddns

echo "DynDNS settings done."


opkg install luci-proto-wireguard luci-app-wireguard
uci set network.wg0=interface
uci set network.wg0.proto='wireguard'
uci set network.wg0.private_key="$WG_KEY"
uci set network.wg0.listen_port='51820'
uci set network.wg0.addresses='192.168.99.1/24'

uci set network.bae=wireguard_wg0
uci set network.bae.description='bae'
uci set network.bae.public_key='is4/cpRQYOogqZ5wwulRxwaHygDobsZT0jlCyHnF6D4='
uci set network.bae.preshared_key="$WG_PRESHARED_KEY"
uci set network.bae.allowed_ips='192.168.99.2/32'
uci set network.bae.route_allowed_ips='1'
uci set network.bae.persistent_keepalive='25'

uci set network.one_plus=wireguard_wg0
uci set network.one_plus.description='one_plus'
uci set network.one_plus.public_key='DcOeAkCLza1RmDz722u0kQfi+U64hA4UxJMQc6BAChU='
uci set network.one_plus.preshared_key="$WG_PRESHARED_KEY"
uci set network.one_plus.allowed_ips='192.168.99.3/32'
uci set network.one_plus.route_allowed_ips='1'
uci set network.one_plus.persistent_keepalive='25'
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

echo "Wireguard settings done."
reload_config


# The luci config file conflicts with the new package
opkg list-upgradable | cut -f 1 -d ' ' | xargs --no-run-if-empty opkg upgrade
# Resolve conflict with an upgraded config file
mv /etc/config/luci-opkg /etc/config/luci || true

echo "Base packages upgraded"


opkg install curl nano coreutils-base64 wget

echo "curl & nano installed."

reload_config
# Remove leases that were made before the static settings
rm -f /tmp/dhcp.leases


echo "Rebooting."
reboot now
