#!/bin/sh -eu

# MWAN3 Multi-WAN load balancer
# NOTE: the ORDER of the traffic rules is important, they are processed in top-down order


. "${0%/*}/utils.sh"

update_opkg
opkg install mwan3 luci-app-mwan3
uci import mwan3 << EOF
config globals 'globals'
	option mmx_mask '0x3F00'

config interface 'wan_bg'
	option enabled '1'
	list track_ip '8.8.4.4'
	list track_ip '8.8.8.8'
	list track_ip '208.67.222.222'
	list track_ip '208.67.220.220'
	option reliability '2'
	option family 'ipv4'

config interface 'wan_jc'
	option enabled '1'
	list track_ip '8.8.4.4'
	list track_ip '8.8.8.8'
	list track_ip '208.67.222.222'
	list track_ip '208.67.220.220'
	option reliability '2'
	option family 'ipv4'

config member 'wan_bg_w1'
	option interface 'wan_bg'
	option metric '1'
	option weight '1'

config member 'wan_jq_w5'
	option interface 'wan_jc'
	option metric '1'
	option weight '5'

config policy 'wan_jc_only'
	list use_member 'wan_bg_w1'

config policy 'wan_bg_only'
	list use_member 'wan_jq_w5'

config policy 'balanced'
	list use_member 'wan_bg_w1'
	list use_member 'wan_jq_w5'

config rule 'wireguard'
	option src_port '51820'
	option proto 'udp'
	option use_policy 'wan_bg_only'
	option family 'ipv4'

config rule 'udp'
	option sticky '1'
	option proto 'udp'
	option use_policy 'balanced'
	option family 'ipv4'

config rule 'https'
	option sticky '1'
	option dest_port '443'
	option proto 'tcp'
	option use_policy 'balanced'
	option family 'ipv4'

config rule 'wan_bg_dns'
	option dest_ip '210.147.235.3,133.205.66.51'
	option family 'ipv4'
	option use_policy 'wan_bg_only'

config rule 'wan_jc_dns'
	option dest_ip '203.165.31.152,122.197.254.136'
	option family 'ipv4'
	option use_policy 'wan_jc_only'

config rule 'default_rule'
	option dest_ip '0.0.0.0/0'
	option family 'ipv4'
	option use_policy 'balanced'
EOF

uci commit mwan3
