#!/bin/sh
set -eu

# Build one device's OpenWrt image with all settings baked in.
# Usage: ./build.sh <device>
# Run inside the Linux build VM (see nix-run.sh / lima-run.sh).

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

# SSH authorized_keys live in a separate repo; fetch them at build time.
PUBKEYS_URL="https://raw.githubusercontent.com/golddranks/pubkeys/main/authorized_keys_strict"

# --- build dependencies ----------------------------------------------------
sudo apt-get install -y build-essential file libncurses-dev zlib1g-dev gawk git \
	libssl-dev xsltproc rsync wget unzip python3 python3-setuptools zstd

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

# --- render overlay (apply secrets.sed to every file in image/<device>/) ---
FILES_DIR="${BUILD_DIR}/files"
rm -rf "${FILES_DIR}"
cp -a "${REPO_DIR}/image/${DEVICE}" "${FILES_DIR}"
find "${FILES_DIR}" -type f -exec sed -i -f "${SECRETS}" {} +

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

# Any '@TOKEN@' left in the rendered overlay means a secret was never
# substituted. Baking a placeholder is silent and dangerous (a literal
# '@WIFI_PW@' passphrase, an '@GANDI_API_KEY@' that always 401s), so refuse.
UNSUBSTITUTED=$(grep -rlE '@[A-Z_][A-Z_0-9]*@' "${FILES_DIR}" 2>/dev/null) || true
if [ -n "${UNSUBSTITUTED}" ]; then
	echo "ERROR: unsubstituted secret token(s) in the rendered overlay:" >&2
	printf '%s\n' "${UNSUBSTITUTED}" >&2
	echo "       Fill them in in secrets.sed (see secrets.sed.example)." >&2
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

# --- build -----------------------------------------------------------------
cd "${BUILD_DIR}/${IB_NAME}"
make image \
	PROFILE="${PROFILE}" \
	PACKAGES="$(grep -v -e '^#' -e '^$' "${SCRIPT_DIR}/packages/${DEVICE}.txt" | tr '\n' ' ')" \
	FILES="${FILES_DIR}"

# --- collect artifacts -----------------------------------------------------
# Only the top-level target files (image, manifest, ...) and the rendered
# overlay; the per-package apk tree is large and only needed during the build.
rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}/targets"
find "bin/targets/${TARGET_PATH}" -maxdepth 1 -type f \
	-exec cp -a {} "${OUT_DIR}/targets/" \;
cp -a "${FILES_DIR}" "${OUT_DIR}/files"

echo
echo "==> ${DEVICE} artifacts in ${OUT_DIR}:"
find "${OUT_DIR}/targets" -maxdepth 1 -type f
