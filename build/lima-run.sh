#!/bin/sh
set -eu

# The guest's unix sockets live under LIMA_HOME, and that path must fit in
# UNIX_PATH_MAX (104 bytes). Keep it short and independent of $TMPDIR, which
# can be very long under a sandboxed/agent terminal.
LIMA_HOME="${HOME}/.cache/monlan-lima"
export LIMA_HOME
mkdir -p "$LIMA_HOME"
chmod 700 "$LIMA_HOME"

# Lima 2.x mounts $HOME read-only by default, but the build writes under build/
# (the rendered overlay and the output image), so mount it writable. Caching
# the sshfs dir listings also makes brand-new files under image/ invisible to
# the guest until the cache expires, so turn it off. These overrides only apply
# when the instance is first created; to change an existing instance, edit its
# lima.yaml and restart it (limactl stop owrt && limactl start owrt).
#
# `start --name ... template:` fails if the instance already exists (lima 2.2),
# so only pass the template when creating it. `limactl start <name>` on its own
# is idempotent: it starts a stopped instance and does nothing if it is running.
if ! limactl list --quiet | grep -qx owrt; then
	limactl start -y --vm-type qemu --arch x86_64 --name owrt \
		--set '.mounts = [{"location": "~", "writable": true, "sshfs": {"cache": false}}]' \
		template:debian
fi

limactl start owrt
limactl shell owrt ./build.sh "$@"
