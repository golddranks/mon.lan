#!/bin/sh
set -eu

# Build one device's OpenWrt image with all settings baked in.
# Run through nix-run.sh, which enters the pinned environment and the VM:
#   ./nix-run.sh <device>

# OpenWrt release. Each device pins the sha256 of its own ImageBuilder tarball.
OPENWRT_VERSION="25.12.6"

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" >/dev/null 2>&1 && pwd -P)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"

DEVICE="${1-}"
# Target, profile and ImageBuilder checksum per device. The checksum belongs to
# the release above, so bump them together.
case "${DEVICE}" in
mon)
	TARGET_PATH="mediatek/filogic"
	PROFILE="glinet_gl-mt6000"
	IB_SHA256="8ce0da1e2fb3d0454ebeb1e3df5705f2145e09ffe6f00d5077c18369719daf83"
	;;
ban)
	TARGET_PATH="ath79/generic"
	PROFILE="tplink_archer-c7-v2"
	IB_SHA256="6f40746139c833336e67b03d5bdb0501d3a80fb789bf7e5b7a9b9984b83a5e23"
	;;
*)
	echo "usage: $0 <device>" >&2
	echo "devices: mon ban" >&2
	exit 1
	;;
esac

# The ImageBuilder tarball is named after the target, not the profile.
IB_TARGET="$(printf '%s' "${TARGET_PATH}" | tr '/' '-')"
IB_NAME="openwrt-imagebuilder-${OPENWRT_VERSION}-${IB_TARGET}.Linux-x86_64"
IB_TAR="${IB_NAME}.tar.zst"
IB_URL="https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/${TARGET_PATH}/${IB_TAR}"

# The repo is mounted from the host over sshfs, which refuses to follow the
# symlinks in the ImageBuilder's host tools ("Operation not permitted"). Do the
# build on the guest's own disk, then copy just the artifacts back into the repo.
BUILD_DIR="/var/tmp/monlan-build/${DEVICE}"
OUT_DIR="${SCRIPT_DIR}/.work/${DEVICE}"

SECRETS="${REPO_DIR}/secrets.sed"
VARS="${SCRIPT_DIR}/vars.sed"

# SSH authorized_keys live in a separate repo; fetch them at build time.
PUBKEYS_URL="https://raw.githubusercontent.com/golddranks/pubkeys/main/authorized_keys_strict"

# --- build dependencies ----------------------------------------------------
sudo apt-get install -y build-essential file gawk git wget unzip python3 zstd acme.sh

# --- clean tree ------------------------------------------------------------
# The image records the commit it came from, so a build refuses a checkout that
# carries changes outside a commit. --no-optional-locks keeps the guest from
# writing the index: this checkout belongs to the host, read over sshfs.
changed=$(git --no-optional-locks -C "${REPO_DIR}" status --porcelain)
if [ -n "${changed}" ]; then
	printf 'refusing to build: the tree carries changes outside a commit:\n%s\n' \
		"${changed}" >&2
	exit 1
fi
COMMIT=$(git --no-optional-locks -C "${REPO_DIR}" rev-parse HEAD)

# --- certificate seed ------------------------------------------------------
# The image carries a current certificate so that a flash does not spend one of
# Let's Encrypt's five issuances per 168 hours for the same name. prepare-cert
# issues through DNS-01 when the seed is inside 30 days of expiry and does
# nothing otherwise; the router keeps renewing its own certificate afterwards.
"${SCRIPT_DIR}/prepare-cert.sh" "${DEVICE}"

# --- secrets ---------------------------------------------------------------
if [ ! -f "${SECRETS}" ]; then
	echo "ERROR: ${SECRETS} not found." >&2
	echo "       cp secrets.sed.example secrets.sed and fill it in." >&2
	exit 1
fi

# --- fetch image builder ---------------------------------------------------
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"
wget -nc -q "${IB_URL}"
echo "${IB_SHA256}  ${IB_TAR}" | sha256sum -c -
rm -rf "${IB_NAME}"
tar --zstd -xf "${IB_TAR}"

# --- render overlay (substitute vars.sed and secrets.sed in every file) -----
FILES_DIR="${BUILD_DIR}/files"
rm -rf "${FILES_DIR}"
cp -a "${REPO_DIR}/image/${DEVICE}" "${FILES_DIR}"
find "${FILES_DIR}" -type f -exec sed -i -f "${VARS}" -f "${SECRETS}" {} +

# git records only the executable bit, so files carried in the overlay arrive
# as 0644. crond would still read the crontab, and mon-send would still read the
# mail config, but neither should be world-readable.
if [ -f "${FILES_DIR}/etc/crontabs/root" ]; then
	chmod 600 "${FILES_DIR}/etc/crontabs/root"
fi
if [ -f "${FILES_DIR}/etc/msmtprc" ]; then
	chmod 600 "${FILES_DIR}/etc/msmtprc"
fi

# The network config carries the WireGuard private keys, so it cannot be
# world-readable.
if [ -f "${FILES_DIR}/etc/config/network" ]; then
	chmod 600 "${FILES_DIR}/etc/config/network"
fi

# --- commit ----------------------------------------------------------------
# Which commit the image came from, so the running box can say it.
printf '%s\n' "${COMMIT}" >"${FILES_DIR}/etc/mon-commit"

# --- validate secrets ------------------------------------------------------
# The root password hash is opaque, so a typo in it is invisible in a diff and
# `crypt()` will simply never match - silently locking you out of the device.
# secrets.sed uses SHA-512 crypt ($6$), whose digest is always 86 characters,
# so refuse to ship anything that is not a complete SHA-512 hash.
ROOT_HASH=$(sed -n 's/^.*root:\([^:]*\):.*/\1/p' \
	"${FILES_DIR}/etc/uci-defaults/99-root-password")
# The '$' characters below are literal grep anchors/escapes, not expansions.
# shellcheck disable=SC2016
printf '%s\n' "${ROOT_HASH}" |
	grep -Eq '^\$6\$[./0-9A-Za-z]{1,16}\$[./0-9A-Za-z]{86}$' || {
	echo "ERROR: root password hash is missing, unsubstituted, or malformed:" >&2
	echo "       '${ROOT_HASH}'" >&2
	echo "       Expected \$6\$<salt>\$<86-character digest>; see secrets.sed." >&2
	exit 1
}

# Any '@TOKEN@' left in the rendered overlay means a value was never
# substituted. Baking a placeholder is silent and dangerous (a literal
# '@WIFI_PW@' passphrase, an '@GANDI_API_KEY@' that always 401s), so refuse.
UNSUBSTITUTED=$(grep -rlE '@[A-Z_][A-Z_0-9]*@' "${FILES_DIR}" 2>/dev/null) || true
if [ -n "${UNSUBSTITUTED}" ]; then
	echo "ERROR: unsubstituted token(s) in the rendered overlay:" >&2
	printf '%s\n' "${UNSUBSTITUTED}" >&2
	echo "       Fill them in in secrets.sed or vars.sed." >&2
	exit 1
fi

# --- ssh keys --------------------------------------------------------------
# Password auth is off (image/<device>/etc/config/dropbear), so the image needs
# a key.
mkdir -p "${FILES_DIR}/etc/dropbear"

# Stable host keys, so a reflash does not invalidate clients' known_hosts.
# Dropbear generates whatever key is missing on first boot; with these present
# it uses them. They are per device and kept out of git (see .gitignore).
if [ -d "${REPO_DIR}/secrets/${DEVICE}" ]; then
	for key in "${REPO_DIR}/secrets/${DEVICE}"/dropbear_*_host_key; do
		[ -f "${key}" ] || continue
		cp "${key}" "${FILES_DIR}/etc/dropbear/"
		chmod 600 "${FILES_DIR}/etc/dropbear/$(basename "${key}")"
	done

	# LuCI's self-signed certificate. uhttpd generates a stock one ("OpenWrt")
	# if these are missing, so baking them keeps the panel's identity sane and
	# stable across reflashes.
	if [ -f "${REPO_DIR}/secrets/${DEVICE}/uhttpd.crt" ]; then
		cp "${REPO_DIR}/secrets/${DEVICE}/uhttpd.crt" "${FILES_DIR}/etc/uhttpd.crt"
		chmod 644 "${FILES_DIR}/etc/uhttpd.crt"
	fi
	if [ -f "${REPO_DIR}/secrets/${DEVICE}/uhttpd.key" ]; then
		cp "${REPO_DIR}/secrets/${DEVICE}/uhttpd.key" "${FILES_DIR}/etc/uhttpd.key"
		chmod 600 "${FILES_DIR}/etc/uhttpd.key"
	fi
fi

wget -q -O "${FILES_DIR}/etc/dropbear/authorized_keys" "${PUBKEYS_URL}" || true
[ -s "${FILES_DIR}/etc/dropbear/authorized_keys" ] ||
	{ echo "ERROR: no SSH keys fetched from ${PUBKEYS_URL}" >&2; exit 1; }
# dropbear walks every component of the key path and refuses any that is
# writable by group/other. The build umask (002) would otherwise leave the
# directory at 0775 and the file at 0664, silently disabling key auth.
chmod 700 "${FILES_DIR}/etc/dropbear"
chmod 600 "${FILES_DIR}/etc/dropbear/authorized_keys"

# --- ghost key --------------------------------------------------------------
# mon's identity wherever it has to run something off the router: the NAT64
# datapath check and the certificate push on ban, and probes from the NixOS
# hosts, where it logs in as the unprivileged ghost user. The pair lives in
# secrets/ghost/ (gitignored) and is split across the images: mon gets the
# private half, ban authorizes the public half.
GHOST_KEY="${REPO_DIR}/secrets/ghost/id_ed25519"
if [ -f "${GHOST_KEY}" ]; then
	case "${DEVICE}" in
	mon)
		install -d -m 700 "${FILES_DIR}/root/.ssh"
		install -m 600 "${GHOST_KEY}" "${FILES_DIR}/root/.ssh/id_ed25519"
		;;
	ban)
		[ -f "${GHOST_KEY}.pub" ] || {
			echo "${GHOST_KEY}.pub is missing; create it with:" >&2
			echo "  ssh-keygen -y -f ${GHOST_KEY} > ${GHOST_KEY}.pub" >&2
			exit 1
		}
		# ban runs mon's probes as the unprivileged ghost user (created at
		# first boot from /etc/ghost), so the key goes there and never into
		# the global authorized_keys, which is root's.
		mkdir -p "${FILES_DIR}/etc/ghost"
		awk '{ print "no-pty,no-port-forwarding,no-agent-forwarding,no-x11-forwarding", $1, $2, "ghost@mon" }' \
			"${GHOST_KEY}.pub" > "${FILES_DIR}/etc/ghost/authorized_keys"
		chmod 700 "${FILES_DIR}/etc/ghost"
		chmod 600 "${FILES_DIR}/etc/ghost/authorized_keys"
		;;
	esac
fi

# --- Let's Encrypt certificates ---------------------------------------------
# `sysupgrade -n` wipes /etc, so the image carries what build/prepare-cert.sh
# seeded in secrets/tls. For mon the certificate alone is not enough: acme-common
# decides between renew and issue by whether /etc/acme/<name>_ecc exists, never
# by the certificate the service loads, so an image with the certificate but no
# store still issues on first boot. Both halves are baked.
# A missing seed is a warning, not an error.
CERT_DIR="${REPO_DIR}/secrets/tls"
ACME_HOME="${SCRIPT_DIR}/.acme"
case "${DEVICE}" in
mon)
	NGINX_SSL="${FILES_DIR}/etc/ssl/nginx"
	if [ -s "${CERT_DIR}/mon.drasa.eu.crt" ] && [ -s "${CERT_DIR}/mon.drasa.eu.key" ]; then
		mkdir -p "${NGINX_SSL}"
		cp "${CERT_DIR}/mon.drasa.eu.crt" "${NGINX_SSL}/mon.drasa.eu.crt"
		cp "${CERT_DIR}/mon.drasa.eu.key" "${NGINX_SSL}/mon.drasa.eu.key"
		chmod 600 "${NGINX_SSL}/mon.drasa.eu.key"
	else
		echo "WARNING: baking no certificate; mon serves the self-signed placeholder until it issues its own." >&2
	fi

	# acme.sh's own store, which is what decides renew vs issue. Only names whose
	# certificate is also being baked are taken, so a name that failed to seed
	# cannot make the image look as if it already had one.
	for name in mon.drasa.eu ban.drasa.eu; do
		[ -s "${CERT_DIR}/${name}.crt" ] || continue
		[ -s "${ACME_HOME}/${name}_ecc/${name}.cer" ] || {
			echo "WARNING: ${name}: no issued store in ${ACME_HOME}; the box issues on first boot." >&2
			continue
		}
		mkdir -p "${FILES_DIR}/etc/acme"
		cp -a "${ACME_HOME}/${name}_ecc" "${FILES_DIR}/etc/acme/"
		# acme.sh records the builder's paths in its config file as the cert
		# install location. Those paths don't exist on the router, so delete
		# those lines from the config file, and let OpenWrt's wrapper do the
		# install.
		sed -i '/^Le_Real[A-Za-z]*Path=/d' \
			"${FILES_DIR}/etc/acme/${name}_ecc/${name}.conf"
	done
	# Only the per-name directories and the account under ca/: account.conf
	# holds the build host's PATH and saved environment, which acme-common
	# supplies itself on the router.
	if [ -d "${FILES_DIR}/etc/acme" ]; then
		cp -a "${ACME_HOME}/ca" "${FILES_DIR}/etc/acme/"
		find "${FILES_DIR}/etc/acme" -name account.key -exec chmod 600 {} +
	fi
	;;
ban)
	# When present this overrides the self-signed pair copied above from
	# secrets/ban; when absent the self-signed pair is the intended fallback.
	if [ -s "${CERT_DIR}/ban.drasa.eu.crt" ] && [ -s "${CERT_DIR}/ban.drasa.eu.key" ]; then
		cp "${CERT_DIR}/ban.drasa.eu.crt" "${FILES_DIR}/etc/uhttpd.crt"
		cp "${CERT_DIR}/ban.drasa.eu.key" "${FILES_DIR}/etc/uhttpd.key"
		chmod 600 "${FILES_DIR}/etc/uhttpd.key"
	fi
	;;
esac

# --- build -----------------------------------------------------------------
cd "${BUILD_DIR}/${IB_NAME}"
make image \
	PROFILE="${PROFILE}" \
	PACKAGES="$(grep -v -e '^#' -e '^$' "${SCRIPT_DIR}/packages/${DEVICE}.txt" | tr '\n' ' ')" \
	FILES="${FILES_DIR}"

# --- collect artifacts -----------------------------------------------------
# Only the top-level target files (image, manifest, ...); the rendered overlay
# stays in the guest, since it carries the substituted secrets.
rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}/targets"
find "bin/targets/${TARGET_PATH}" -maxdepth 1 -type f \
	-exec cp -a {} "${OUT_DIR}/targets/" \;

# --- package set ------------------------------------------------------------
# The ImageBuilder tarball is pinned by checksum, but the package feeds are not:
# they are fetched at build time and updated in place (luci and uhttpd moved
# between two builds a day apart). The recorded manifest is the lock, so a build
# that resolves different versions stops here instead of shipping them silently.
MANIFEST="${SCRIPT_DIR}/manifests/${DEVICE}.manifest"
built_manifest=$(find "${OUT_DIR}/targets" -maxdepth 1 -name '*.manifest' | head -n 1)
if [ -n "${built_manifest}" ] && [ -f "${MANIFEST}" ]; then
	if ! diff -u "${MANIFEST}" "${built_manifest}" >"${BUILD_DIR}/manifest.diff"; then
		echo "ERROR: resolved package versions differ from ${MANIFEST}:" >&2
		cat "${BUILD_DIR}/manifest.diff" >&2
		echo >&2
		echo "The image in ${OUT_DIR} is built from this set. If the change is" >&2
		echo "acceptable, record it and keep the image; no rebuild is needed:" >&2
		echo "  cp '${built_manifest}' '${MANIFEST}'" >&2
		exit 1
	fi
elif [ -n "${built_manifest}" ]; then
	echo "NOTE: no ${MANIFEST}; record the package set with:" >&2
	echo "  cp '${built_manifest}' '${MANIFEST}'" >&2
fi

echo
echo "==> ${DEVICE} artifacts in ${OUT_DIR}:"
find "${OUT_DIR}/targets" -maxdepth 1 -type f
