#!/bin/sh -eu

PPP_ID=${1:?}
PPP_PW=${2:?}
WIFI_PW=${3:?}

echo "Installing."

uci set network.wan.proto='pppoe'
uci set network.wan.username="$PPP_ID"
uci set network.wan.password="$PPP_PW"
uci commit network

uci set wireless.default_radio0.ssid='Skeletor 5Ghz'
uci set wireless.default_radio0.key="$WIFI_PW"
uci set wireless.default_radio0.encryption='psk2'
uci set wireless.default_radio1.ssid='Skeletor 2.5Ghz'
uci set wireless.default_radio1.key="$WIFI_PW"
uci set wireless.default_radio1.encryption='psk2'
uci delete wireless.radio1.disabled
uci commit wireless

uci set dropbear.RootPasswordAuth='off'
uci set dropbear.PasswordAuth='off'
uci commit dropbear

uci set system.@system[0].hostname='mon'
uci set system.@system[0].timezone='Asia/Tokyo'
uci commit system

reload_config


# set HTTPS
# set IPv6
# set DHCP ranges
# wireguard
# set up dyndns
# set up ports
# set up wifi one-push
