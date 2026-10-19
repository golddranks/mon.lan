#!/bin/sh
# shellcheck disable=SC1091,SC2154,SC3043
# Gandi LiveDNS update script using a Bearer token.
#
# Sourced by ddns-scripts, which provides the variables used below.
#
# ddns-scripts 2.8.4 ships a version that still sends `Authorization: Apikey`,
# which Gandi rejects for personal access tokens. This is the upstream fix; the
# image installs it over the packaged copy.

. /usr/share/libubox/jshn.sh

local __TTL=600
local __RRTYPE
local __ENDPOINT="https://api.gandi.net/v5/livedns"
local __STATUS

[ -z "$username" ] && write_log 14 "Service section not configured correctly! Missing subdomain as 'username'"
[ -z "$password" ] && write_log 14 "Service section not configured correctly! Missing API Key as 'password'"

[ "$use_ipv6" -ne 0 ] && __RRTYPE="AAAA" || __RRTYPE="A"

# Construct JSON payload
json_init
json_add_int rrset_ttl "$__TTL"
json_add_array rrset_values
json_add_string "" "$__IP"
json_close_array

set -- curl -s -X PUT \
	"$__ENDPOINT/domains/$domain/records/$username/$__RRTYPE" \
	-H "Authorization: Bearer $password" \
	-H "Content-Type: application/json" \
	-d "$(json_dump)" \
	--connect-timeout 30 \
	-w "%{http_code}" \
	-o "$DATFILE"

write_log 7 "Running: $* 2>$ERRFILE"

__STATUS=$("$@" 2>"$ERRFILE")

local __ERRNO=$?
if [ "$__ERRNO" -ne 0 ]; then
	write_log 4 "Curl failed with $__ERRNO: $(cat "$ERRFILE")"
	return 1
elif [ -z "$__STATUS" ] || [ "$__STATUS" != 201 ]; then
	write_log 4 "LiveDNS failed: $__STATUS; gandi.net answered: $(cat "$DATFILE")"
	return 1
fi

write_log 7 "gandi.net answered: $(cat "$DATFILE")"

return 0
