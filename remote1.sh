#!/bin/sh -eu

ROOT_PW=${1:?}
SSH_PUBKEY=${2:?}
PPP_ID=${3:?}
PPP_PW=${4:?}
WIFI_PW=${5:?}


echo "Setting up config on TP-Link Archer C7 v2.0/JP. OS: OpenWrt 19.07.5."

# Add the host pubkey of the installer host
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
uci set dropbear.cfg014dd4.Interface='lan'
uci commit dropbear

echo "Security config done."


# Lan
uci set network.lan.ipaddr='10.0.0.1'
uci set network.lan.ip6ifaceid='::1'

# Internet
uci set network.wan.proto='pppoe'
uci set network.wan.username="$PPP_ID"
uci set network.wan.password="$PPP_PW"

# IPv6
uci set network.wan6.proto='dhcpv6'
uci set network.wan6.ifaceid='::1'
# MacOS NDP+RA IPv6 address selection supports only LLA source addresses, so don't use ULA:
uci set network.globals.ula_prefix=''

uci commit network

# Wifi
uci set wireless.default_radio0.ssid='Skeletor 5Ghz'
uci set wireless.default_radio0.key="$WIFI_PW"
uci set wireless.default_radio0.encryption='psk2'
uci set wireless.radio0.disabled='0'
uci set wireless.radio0.country='JP'
uci set wireless.default_radio1.ssid='Skeletor 2.5Ghz'
uci set wireless.default_radio1.key="$WIFI_PW"
uci set wireless.default_radio1.encryption='psk2'
uci set wireless.radio1.disabled='0'
uci set wireless.radio1.country='JP'
uci commit wireless

# General system settings
uci set system.cfg01e48a.hostname='mon'
uci set system.cfg01e48a.timezone='JST-9'
uci set system.cfg01e48a.zonename='Asia/Tokyo'
uci commit system

# Set LAN to relay mode to support NDP+RA based IPv6 addressing
uci set dhcp.lan.ra='relay'
uci set dhcp.lan.dhcpv6='relay'
uci set dhcp.lan.ndp='relay'
# Add WAN6 interface, set it to relay mode and master:
uci set dhcp.wan6=dhcp
uci set dhcp.wan6.interface='wan6'
uci set dhcp.wan6.ignore='1'
uci set dhcp.wan6.master='1'
uci set dhcp.wan6.dhcpv6='relay'
uci set dhcp.wan6.ra='relay'
uci set dhcp.wan6.ndp='relay'
uci commit dhcp

echo "Basic network config done."


# Set DHCP static leases
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

uci set dhcp.poi=host
uci set dhcp.poi.name='bae'
uci set dhcp.poi.mac='F4:5C:89:AA:C3:DD'
uci set dhcp.poi.ip='10.0.0.30'
uci set dhcp.poi.hostid='30'
uci set dhcp.poi.dns='1'
uci commit dhcp

echo "DHCP static lease settings done."


# Port forwarding (expose poi SSH)
uci set firewall.ssh_redirect=redirect
uci set firewall.ssh_redirect.target='DNAT'
uci set firewall.ssh_redirect.name='SSH'
uci set firewall.ssh_redirect.src='wan'
uci set firewall.ssh_redirect.src_dport='22'
uci set firewall.ssh_redirect.dest_ip='10.0.0.20'
uci set firewall.ssh_redirect.dest_port='22'
uci commit firewall

echo "Port forwarding settings done."


# Remove leases that were made before the static DHCP settings
rm -f /tmp/dhcp.leases

echo "Rebooting."
reboot now