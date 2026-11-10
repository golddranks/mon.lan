#!/bin/sh
# prepare-cert.sh <device> - seed secrets/tls with the Let's Encrypt certificate
# that device's image carries, before it is built.
#
# Runs inside the build VM, after build.sh has installed acme.sh. Each router
# renews its own certificate live; this exists so that a flash does not spend one
# of Let's Encrypt's five issuances per 168 hours for the same name. The seed is
# only half of that: the router's ACME client decides by the store it keeps in
# /etc/acme, which build.sh bakes alongside the certificate. A seed that is still
# good for more than RENEW_DAYS is reused as it is, so an ordinary build talks to
# nothing.
#
# mon.drasa.eu and ban.drasa.eu are separate certificates on purpose: a shared
# one would put a key valid for mon.drasa.eu into ban's overlay. Each device
# prepares only its own, so a build cannot spend the other device's quota.
#
# Validation is DNS-01: control is proved by a temporary TXT record written
# through the Gandi API, so no inbound path to the routers is involved.
#
# Every failure here is a warning: an image without a fresh certificate still
# boots, and the device issues or receives its own later.
set -eu

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" >/dev/null 2>&1 && pwd -P)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"

case "${1-}" in
mon) NAMES="mon.drasa.eu" ;;
ban) NAMES="ban.drasa.eu" ;;
*)
	echo "usage: $0 <device>" >&2
	exit 1
	;;
esac
OUT="${REPO_DIR}/secrets/tls"
ACME_HOME="${SCRIPT_DIR}/.acme"
RENEW_DAYS=30

# `secrets/` and `build/.acme` are on the host, reached over the build VM's
# sshfs mount, so chmod is best-effort and must not abort the build.
mkdir -p "$OUT" 2>/dev/null || true
chmod 700 "$OUT" 2>/dev/null || true

# A seed we can reuse: present, and valid for longer than RENEW_DAYS.
seed_is_fresh() {
	[ -s "$OUT/$1.crt" ] && [ -s "$OUT/$1.key" ] || return 1
	openssl x509 -in "$OUT/$1.crt" -noout -checkend "$((RENEW_DAYS * 86400))" \
		>/dev/null 2>&1
}

stale=
for n in $NAMES; do
	seed_is_fresh "$n" || stale="$stale $n"
done
if [ -z "$stale" ]; then
	echo "prepare-cert: seed is good for more than $RENEW_DAYS days, reusing it" >&2
	exit 0
fi

TOKEN=$(sed -n 's/^s|@GANDI_API_KEY@|\([^|]*\)|.*$/\1/p' "${REPO_DIR}/secrets.sed")
if [ -z "$TOKEN" ]; then
	echo "prepare-cert: no @GANDI_API_KEY@ in secrets.sed; building without fresh certificates" >&2
	exit 0
fi
GANDI_LIVEDNS_TOKEN="$TOKEN"
export GANDI_LIVEDNS_TOKEN

mkdir -p "$ACME_HOME" 2>/dev/null || true

for n in $stale; do
	# Returns 0 when issued, 2 when the cached certificate is still valid and
	# was left alone. Both mean the home holds a usable certificate afterwards.
	set +e
	acme.sh --home "$ACME_HOME" --server letsencrypt --keylength ec-256 \
		-d "$n" --dns dns_gandi_livedns --issue
	rc=$?
	set -e
	if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
		echo "prepare-cert: $n: issuance failed (acme.sh exit $rc); building without it" >&2
		continue
	fi

	set +e
	acme.sh --home "$ACME_HOME" --ecc -d "$n" --install-cert \
		--key-file "$OUT/$n.key" --fullchain-file "$OUT/$n.crt"
	rc=$?
	set -e
	if [ "$rc" -ne 0 ]; then
		echo "prepare-cert: $n: install-cert failed (acme.sh exit $rc); building without it" >&2
		continue
	fi
	chmod 600 "$OUT/$n.key" 2>/dev/null || true

	if seed_is_fresh "$n"; then
		echo "prepare-cert: seeded $n" >&2
	else
		echo "prepare-cert: $n is still inside $RENEW_DAYS days" >&2
	fi
done
exit 0
