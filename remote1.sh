#!/bin/sh -eu

ROOT_PW=${1:?}
SSH_PUBKEY=${2:?}
PPP_ID=${3:?}
PPP_PW=${4:?}
WIFI_PW=${5:?}


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
uci set dropbear.cfg014dd4.Interface='lan'
uci commit dropbear

echo "Security config done."

uci set network.lan.ipaddr='10.0.0.1'
uci set network.lan.ip6ifaceid='::1'
uci set network.wan.proto='pppoe'
uci set network.wan.username="$PPP_ID"
uci set network.wan.password="$PPP_PW"
#uci set network.wan6.proto='static'
#uci set network.wan6.ip6ifaceid='::1'
uci commit network

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

uci set system.cfg01e48a.hostname='mon'
uci set system.cfg01e48a.timezone='JST-9'
uci set system.cfg01e48a.zonename='Asia/Tokyo'
uci commit system


echo "Basic network config done. Rebooting."
reboot now