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

## Wireless

- Both radios are baked in `/etc/config/wireless`: 2.4 GHz (`radio0`) and
  5 GHz (`radio1`), country `JP`, WPA2-PSK (the key comes from `secrets.sed`).
- One SSID on both bands, so clients pick the band themselves. No 802.11r (it
  only matters with more than one AP).

## Web UI / TLS

- LuCI is served by **nginx** through uwsgi; `nginx-mod-luci`'s uci-defaults
  disables uhttpd on first boot. `http://` returns a 301 to `https://`.
- Two HTTPS server parts (`/etc/config/nginx`): `_lan` is the LAN-only
  default_server with a self-signed certificate (reach it by IP), and
  `mon.drasa.eu` carries a **Let's Encrypt** certificate.
- The certificate is issued over **DNS-01** - a `_acme-challenge` TXT record
  written through the Gandi API - so nothing is exposed to the WAN
  (`/etc/config/acme`). `/etc/config/dhcp` resolves `mon.drasa.eu` to the
  router, so the panel works on the LAN without publishing the name.
- A self-signed placeholder is generated on first boot so nginx always starts;
  `/etc/hotplug.d/acme/90-nginx-cert` swaps in the real certificate and reloads
  nginx whenever it is issued or renewed. The first issuance is triggered when
  the WAN comes up (`/etc/hotplug.d/iface/90-acme`); acme-common itself only
  schedules the nightly renewals.

## Repository layout

```
build/
  build.sh            download the ImageBuilder, render the overlay, make image
  packages.txt        packages to bake in ('-name' removes a default)
  flake.nix           pinned lima (qemu x86_64) build environment
  nix-run.sh          entry point: nix shell .#lima --command ./lima-run.sh
  lima-run.sh         start the VM and run build.sh inside it
image/                rootfs overlay, rendered then merged into the image (/etc/...)
  etc/config/         UCI: network, system, dhcp, firewall, dropbear, wireless, jool, unbound, ddns, nginx, acme
  etc/jool/           Jool NAT64 instance definition (created at boot)
  etc/hotplug.d/      certificate handoff (acme) and first-issuance trigger (iface)
  etc/uci-defaults/   first-boot-only scripts (self-deleting)
secrets.sed.example   sed substitutions for the overlay's @NAME@ tokens
```

## Building

Requires Nix and the ability to run an x86_64 VM via lima/qemu.

```sh
cd build
cp ../secrets.sed.example ../secrets.sed   # then fill in every token
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

- DDNS: the Gandi provider plumbing is in place (`/etc/config/ddns`, API key
  from `secrets.sed`), but no record is enabled yet. Publishing a LAN host's
  AAAA is only useful together with a firewall opening for that host, so the
  per-host policy has to be decided first.

## Notes

- Confirm `eth1` / `lan1..lan5` on the running device before relying on the port
  map.
- SSH is key-only: `authorized_keys` is fetched from the `pubkeys` repo at build
  time. The root password from `secrets.sed` is used for LuCI and the console.
