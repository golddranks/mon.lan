#!/bin/sh
set -eu

# Build a GL.iNet MT6000 (Flint 2) OpenWrt image with all settings baked in.
# Run inside the Linux build VM (see nix-run.sh / lima-run.sh).

# OpenWrt release, and the sha256 of its ImageBuilder tarball. Bump together.
OPENWRT_VERSION="25.12.5"
IB_SHA256="7fb6cf626582ebcbfb46974da48c1eae577213f38879eaf6b1d982041e843461"

PROFILE="glinet_gl-mt6000"
TARGET_PATH="mediatek/filogic"

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" >/dev/null 2>&1 && pwd -P)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"

# The repo is mounted from the host over sshfs, which refuses to follow the
# symlinks in the ImageBuilder's host tools ("Operation not permitted"). Do the
# build on the guest's own disk, then copy just the artifacts back into the repo.
BUILD_DIR="/var/tmp/monlan-build"
OUT_DIR="${SCRIPT_DIR}/.work"

SECRETS="${REPO_DIR}/secrets.sed"

IB_NAME="openwrt-imagebuilder-${OPENWRT_VERSION}-mediatek-filogic.Linux-x86_64"
IB_TAR="${IB_NAME}.tar.zst"
IB_URL="https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/${TARGET_PATH}/${IB_TAR}"

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

# --- render overlay (apply secrets.sed to every file in image/) ------------
FILES_DIR="${BUILD_DIR}/files"
rm -rf "${FILES_DIR}"
cp -a "${REPO_DIR}/image" "${FILES_DIR}"
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

# --- ssh keys --------------------------------------------------------------
# Password auth is off (image/etc/config/dropbear), so the image needs a key.
mkdir -p "${FILES_DIR}/etc/dropbear"
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
	PACKAGES="$(grep -v -e '^#' -e '^$' "${SCRIPT_DIR}/packages.txt" | tr '\n' ' ')" \
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
echo "==> Artifacts in ${OUT_DIR}:"
find "${OUT_DIR}/targets" -maxdepth 1 -type f
