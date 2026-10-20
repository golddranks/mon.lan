# mon.lan

OpenWrt images for a two-AP home network. All configuration is baked into each
image itself via the ImageBuilder's `FILES` overlay.

| Device  | Hardware                 | Target / profile                       | Role       |
| ------- | ------------------------ | -------------------------------------- | ---------- |
| `mon`   | GL.iNet MT6000 (Flint 2) | `mediatek/filogic`, `glinet_gl-mt6000` | router, AP |
| `tsugi` | TP-Link Archer C7 v2     | `ath79/generic`, `tplink_archer-c7-v2` | dumb AP    |

```
J:COM ── eth1 [mon] br-lan ══════ cable ══════ br-lan [tsugi] ~~ SSID "Skeletor"
```

## mon

### Network

- **WAN** runs DHCPv4 and DHCPv6-PD, requesting a **/56** from the ISP (J:COM).
- **LAN** is **IPv6-only**: no IPv4 address and no DHCPv4. Hosts get addresses
  over SLAAC and DHCPv6 (`odhcpd`), using GUA addresses from the delegated /56
  plus a fixed ULA (`fd42:6d6f:6e00::/48`) for stable internal addresses.
- IPv4-only destinations are reached via **NAT64 + DNS64**: unbound (behind
  dnsmasq) synthesises AAAA records in the well-known `64:ff9b::/96` prefix, and
  Jool translates that traffic out to the WAN's IPv4 address. The prefix is also
  advertised on the LAN (`ra_pref64`) so dual-stack-aware clients can build a
  CLAT for apps that never received a synthesised AAAA (464XLAT).
- `bitwarden`, `syncthing` and `webshare` (all on mame) are published in
  Gandi LiveDNS (`/etc/config/ddns`): A records for the WAN IPv4, AAAA records
  for mame's GUA. mame pins its SLAAC suffix (`slaac token ::10`), so the AAAA
  is the delegated /64 plus `::10` (`/usr/lib/ddns/lan_suffix.sh`). The apex and
  `jcom.drasa.eu` are not published.
- Inbound, IPv6 TCP 22/80/443 is forwarded to every LAN host unchanged (no
  NAT66); the router's own input stays closed. IPv4 TCP 80/443 terminates on
  the router, where nginx proxies to mame (see below).
- Names served locally: `mon.drasa.eu` and `tsugi.lan` are static entries in
  `/etc/config/dhcp`, both pointing at ULAs, so they work without a lease and
  without a delegated prefix.

### Wireless

- Both radios are baked in `/etc/config/wireless`: 2.4 GHz (`radio0`, channel 1)
  and 5 GHz (`radio1`, channel 36), country `JP`, WPA2-PSK (the key comes from
  `secrets.sed`).
- One SSID on both bands, so clients pick the band themselves. No 802.11r: it
  only matters with more than one AP, and tsugi has to be configured to match.

### Web UI / TLS

- LuCI is served by **nginx** through uwsgi; `nginx-mod-luci`'s uci-defaults
  disables uhttpd on first boot. `http://` returns a 301 to `https://`.
- Two HTTPS server parts (`/etc/config/nginx`): `_lan` is the LAN-only
  default_server with a self-signed certificate (reach it by IP), and
  `mon.drasa.eu` carries a **Let's Encrypt** certificate.
- The certificate is issued over **DNS-01** - a `_acme-challenge` TXT record
  written through the Gandi API - so issuance needs no inbound HTTP
  (`/etc/config/acme`). `/etc/config/dhcp` still resolves `mon.drasa.eu` to the
  ULA on the LAN, so the name keeps working when the WAN is down.
- The HTTP server listens on **IPv6 only**; the LAN is IPv6-only and IPv4
  `:80`/`:443` belong to nginx's `stream` proxy (`/etc/nginx/stream.d`). HTTPS
  is routed by SNI to mame's ULA (`fd42:6d6f:6e00::10`), so the TLS connection
  passes through and mame keeps its own certificates; plain HTTP has a single
  backend. A name on another host is one more `map` entry for 443 (per-host
  routing for port 80 would need an L7 proxy).
- A self-signed placeholder is generated on first boot so nginx always starts;
  `/etc/hotplug.d/acme/90-nginx-cert` swaps in the real certificate and reloads
  nginx whenever it is issued or renewed. The first issuance is triggered when
  the WAN comes up (`/etc/hotplug.d/iface/90-acme`); acme-common itself only
  schedules the nightly renewals.
- NTP is also served to the LAN (`enable_server` plus `interface lan`): tsugi
  has no address that can reach an upstream clock.

## tsugi

A dumb AP: it bridges, and does nothing else.

- One bridge `br-lan` over `eth1`, which is the LAN CPU port of the board's
  **swconfig** switch (`0u@eth1` in the target's `board.d`; the WAN side would
  be CPU port 6 on `eth0`). The bridge is over `eth1`, not `eth1.1` - the CPU
  port is untagged and there is no VLAN interface to bridge.
- All five physical ports are in that one VLAN, so the cable from mon can go
  into any of them; there is no dead "WAN" port.
- Management address is a static ULA, `fd42:6d6f:6e00::2/64`, with **no
  default route**. It is deliberately not a GUA: mon forwards inbound IPv6 TCP
  22/80/443 to every LAN host, so a global address would put this AP's LuCI on
  the internet. `tsugi.lan` resolves to that ULA from mon's resolver.
- `dnsmasq` and `odhcpd` are not installed: mon is the only DHCP, RA and DNS
  server on the LAN, and a second one would only confuse clients.
- LuCI is the stock `uhttpd` with `luci-ssl`, i.e. HTTPS with a self-signed
  certificate generated on first boot; the browser warning is expected. SSH is
  key-only, like mon.
- Time comes from mon (`fd42:6d6f:6e00::1`); with no default route there is
  nowhere else to get it.
- Same SSID and key as mon, on offset channels (2.4 GHz: 6, 5 GHz: 52) so the
  two APs do not sit on top of each other. Channel 52 is DFS, so the 5 GHz radio
  waits out the channel availability check before it starts.

## Repository layout

```
build/
  build.sh              build one device: ./build.sh <device>
  devices/<device>.conf target, profile and ImageBuilder checksum
  packages/<device>.txt packages to bake in ('-name' removes a default)
  flake.nix             pinned lima (qemu x86_64) build environment
  nix-run.sh            entry point: nix shell .#lima --command ./lima-run.sh
  lima-run.sh           start the VM and run build.sh inside it
image/
  mon/                  rootfs overlay for mon (/etc/..., /usr/...)
  tsugi/                rootfs overlay for tsugi (/etc/...)
secrets.sed.example     sed substitutions for the overlays' @NAME@ tokens
```

## Building

Requires Nix and the ability to run an x86_64 VM via lima/qemu.

```sh
cd build
cp ../secrets.sed.example ../secrets.sed   # then fill in every token
./nix-run.sh mon
./nix-run.sh tsugi
```

`build.sh` sources `devices/<device>.conf`, verifies the pinned ImageBuilder
tarball against its sha256, copies `image/<device>/` into the build while
applying `secrets.sed` (sed substitutions that fill in the overlay's `@NAME@`
tokens), fetches `authorized_keys` from the `pubkeys` repo, and runs `make
image`. The OpenWrt release is pinned by `OPENWRT_VERSION` in `build.sh` and the
package set comes from `packages/<device>.txt`; artifacts land under
`build/.work/<device>/`.

The images contain the baked credentials, so treat the output `.bin` files as
secrets.

## Flashing

- Both devices use `sysupgrade` with the `*-squashfs-sysupgrade.bin` from
  `build/.work/<device>/targets/`.
- `sysupgrade` preserves `/etc/config` by default; use `sysupgrade -n` to make
  the image's baked configuration authoritative on every upgrade.
- mon's first install from GL.iNet stock firmware needs the official factory
  image (or the u-boot recovery path). tsugi is already on OpenWrt, so
  `sysupgrade` is enough; from stock TP-Link firmware it would need the
  `-factory.bin` the build also produces.
- After flashing tsugi, reach it at `https://tsugi.lan/` or
  `https://[fd42:6d6f:6e00::2]/` over the LAN.

## How settings persist

- `/bin/config_generate` exits early when both `/etc/config/network` and
  `/etc/config/system` are non-empty, so device detection never overwrites the
  baked configuration.
- `/etc/uci-defaults/*` runs once on first boot (from `/etc/init.d/boot`) and is
  then deleted; this is where the root password hash is applied.
- A factory reset (`firstboot`) clears the overlay but keeps the baked config, so
  the device returns to this image's configuration, not blank OpenWrt defaults.

## Not yet implemented

- IPv4-only devices (the Nintendo Switch, the air conditioner, the doorbell)
  have no segment yet. The plan is a second SSID on a `br-iot` bridge with
  NAT, so those clients never see the IPv6-only LAN.
- Roaming: one SSID on two APs already works, but 802.11r/11k/11v would make
  handoff faster. It needs the same settings on both devices, so it is a change
  to `mon` and `tsugi` at once.

## Notes

- On mon, confirm `eth1` / `lan1..lan5` on the running device before relying on
  the port map.
- On tsugi, each radio is matched by the tail of its sysfs device path
  (`0000:00:00.0` for the PCIe card, `18100000.wmac` for the AHB MAC). If a
  radio does not come up, check `logread` - a wrong path is the first suspect.
- SSH is key-only: `authorized_keys` is fetched from the `pubkeys` repo at build
  time. The root password from `secrets.sed` is used for LuCI and the console.
