# mon.lan

OpenWrt image for the **GL.iNet MT6000 (Flint 2)** router. All configuration is
baked into the image itself via the ImageBuilder's `FILES` overlay.

## Target device

- Target `mediatek/filogic`, profile `glinet_gl-mt6000` (MediaTek MT7986A,
  aarch64; 1 GB RAM, 8 GB eMMC).
- WAN is `eth1` (2.5G); LAN is the bridge `lan1 lan2 lan3 lan4 lan5`. These
  device names come from the target's `board.d/02_network`.

## Network

- **WAN** runs DHCPv4 and DHCPv6-PD, requesting a **/56** from the ISP (J:COM).
- **LAN** is **IPv6-only**: no IPv4 address and no DHCPv4. Hosts get addresses
  over SLAAC and DHCPv6 (`odhcpd`), using GUA addresses from the delegated /56
  plus a fixed ULA (`fd42:6d6f:6e00::/48`) for stable internal addresses.
- IPv4-only destinations are reached via **NAT64 + DNS64**: unbound (behind
  dnsmasq) synthesises AAAA records in the well-known `64:ff9b::/96` prefix, and
  Jool translates that traffic out to the WAN's IPv4 address. The prefix is also
  advertised on the LAN (`ra_pref64`) so dual-stack-aware clients can build a
  CLAT for apps that never received a synthesised AAAA (464XLAT).

## Repository layout

```
build/
  build.sh            download the ImageBuilder, render the overlay, make image
  packages.txt        packages to bake in ('-name' removes a default)
  flake.nix           pinned lima (qemu x86_64) build environment
  nix-run.sh          entry point: nix shell .#lima --command ./lima-run.sh
  lima-run.sh         start the VM and run build.sh inside it
image/                rootfs overlay, rendered then merged into the image (/etc/...)
  etc/config/         UCI: network, system, dhcp, firewall, dropbear, jool, unbound
  etc/jool/           Jool NAT64 instance definition (created at boot)
  etc/uci-defaults/   first-boot-only scripts (self-deleting)
secrets.sed.example   sed substitutions for the overlay's @NAME@ tokens
```

## Building

Requires Nix and the ability to run an x86_64 VM via lima/qemu.

```sh
cd build
cp ../secrets.sed.example ../secrets.sed   # then set ROOT_PW_HASH
./nix-run.sh
```

`build.sh` verifies the pinned ImageBuilder tarball against its sha256, copies
`image/` into the build while applying `secrets.sed` (sed substitutions that
fill in the overlay's `@NAME@` tokens), fetches `authorized_keys` from the
`pubkeys` repo, and runs `make image`. The OpenWrt release is pinned by
`OPENWRT_VERSION` (25.12.5) and the package set comes from `packages.txt`;
artifacts land under `build/.work/`.

The image contains the baked credentials, so treat the output `.bin` as a secret.

## Flashing

- Flash the `*-squashfs-sysupgrade.bin` from `build/.work/` with `sysupgrade`.
  The first install from GL.iNet stock firmware needs the official factory image
  (or the u-boot recovery path).
- `sysupgrade` preserves `/etc/config` by default; use `sysupgrade -n` to make
  the image's baked configuration authoritative on every upgrade.

## How settings persist

- `/bin/config_generate` exits early when both `/etc/config/network` and
  `/etc/config/system` are non-empty, so device detection never overwrites the
  baked configuration.
- `/etc/uci-defaults/*` runs once on first boot (from `/etc/init.d/boot`) and is
  then deleted; this is where the root password hash is applied.
- A factory reset (`firstboot`) clears the overlay but keeps the baked config, so
  the device returns to this image's configuration, not blank OpenWrt defaults.

## Not yet implemented

- Wireless: SSID, country, and 802.11r (radios are currently left to
  `wifi config`).
- DDNS: per-service AAAA records for LAN hosts, updated when the delegated /56
  changes.
- nginx TLS.

## Notes

- Confirm `eth1` / `lan1..lan5` on the running device before relying on the port
  map.
- SSH is key-only: `authorized_keys` is fetched from the `pubkeys` repo at build
  time. The root password from `secrets.sed` is used for LuCI and the console.
