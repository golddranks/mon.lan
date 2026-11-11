# mon.lan

OpenWrt images for a two-AP home network, with every setting baked in at build
time.

| Device | Hardware                 | Target / profile                       | Role       |
| ------ | ------------------------ | -------------------------------------- | ---------- |
| `mon`  | GL.iNet MT6000 (Flint 2) | `mediatek/filogic`, `glinet_gl-mt6000` | router, AP |
| `ban`  | TP-Link Archer C7 v2     | `ath79/generic`, `tplink_archer-c7-v2` | dumb AP    |

## mon

- **WAN** DHCPv4 + DHCPv6-PD (/56), with a fixed DHCPv6 identity. **LAN** is
  IPv6-only: no IPv4, no DHCPv4; the GUA is the first /64 of the delegation, so
  it follows the prefix, plus ULA `fd42:6d6f:6e00::/48` for stable names.
- **NAT64 + DNS64**: IPv4-only destinations are reachable from the IPv6-only
  LAN; unbound synthesises the AAAA and Jool translates to the WAN address, and
  some clients build their own CLAT (464XLAT).
- **VPN**: two WireGuard interfaces. `SkeletoriLanVPN` is a second /64 in the
  ULA, forwarded to the LAN with no NAT, for reaching LAN hosts from anywhere;
  `SkeletoriJailVPN` is IPv4-only, NATted to the WAN and has no route to the
  LAN, for browsing as if from home. Peers live in `/etc/wireguard/<interface>.tsv`
  and are added to their interfaces at first boot.
- **DDNS** (Gandi): A + AAAA for `bitwarden`, `syncthing`, `webshare`, `cafe`;
  AAAA only for `bead` and `llm`. The AAAA is the host's LAN address. `vpn`
  publishes both WAN addresses instead, which is how the WireGuard profiles
  find the router.
- Inbound TCP 80/443 is forwarded to LAN hosts while the router's own input
  stays closed.
- `mon.lan`, `ban.lan`, `mon.drasa.eu`, `ban.drasa.eu`, `bead.lan`,
  `bead.drasa.eu` and `llm.drasa.eu` (bead's LLM vhost): static ULA entries;
  the `*.drasa.eu` ones also resolve publicly.
- **Jail**: `SkeletorJail` on radio0 (2.4 GHz) over `br-iot`, `10.10.1.1/24`,
  DHCPv4 and masquerade to the WAN, no IPv6, WPA2/WPA3 mixed and client
  isolation - for devices that cannot use the IPv6-only LAN or WPA3.
- **Wireless**: one SSID on both bands (ch 1 / 36, `JP`, WPA3-SAE with the PSK
  from `secrets.sed`, PMF required), 802.11r and 802.11k/v; `usteer` steers over
  IPv6.
- **LuCI**: reachable on the LAN with a self-signed cert, and as `mon.drasa.eu`
  with a Let's Encrypt one issued through the DNS zone, so no inbound port is
  needed for it. IPv4 :80 redirects to HTTPS; IPv4 :443 is routed by name to
  cafe, which keeps its own certificates.
- **Diagnostics**: `netdiag` checks the invariants and exits non-zero on
  failure; `mon-watch` runs it every 10 min and mails when the failing set or a
  watched value (the delegation, the LAN GUA) changes, so a clean renumbering is
  still reported (known temporary states are silenced); `mon-weekly` mails
  netdiag, addressing, routes, Jool counters and the last kernel log lines;
  failed sends are logged to `/root/mon-notify.log`.

## ban

A dumb AP: it bridges, nothing else.

- All five ethernet ports are one bridge, so the uplink can use any port.
- Static ULA `fd42:6d6f:6e00::2/64`; LuCI and SSH answer only there and on
  link-local. It takes a default route from mon's Router Advertisements but
  ignores their prefix information, so it forms no GUA — nothing on ban is
  reachable through a routed prefix — and the netdiag datapath probe sources
  from the ULA. No `dnsmasq`/`odhcpd`: mon is the only DHCP, RA and DNS server.
- Stock LuCI; it serves a Let's Encrypt certificate, staged by mon over the
  ghost key and installed by root's cron. SSH key-only: root for you, `ghost`
  for mon's probes; time from mon. Offset channels (2.4 GHz: 6, 5 GHz: 52 — DFS).

## Layout and building

```
build/nix-run.sh        enter the pinned environment, then ./lima-run.sh
build/lima-run.sh       start the Linux VM and run build.sh in it
build/build.sh          build one device
build/packages/         packages to bake in ('-name' removes a default)
build/manifests/        resolved package sets; a build fails if one changes
build/vars.sed          values substituted into the overlay (@ULA@, @FT_MDID@)
build/flake.nix         pinned lima (qemu x86_64) environment
image/mon/  image/ban/  rootfs overlays, with @TOKEN@ placeholders
LEARNINGS.md            assumptions that turned out wrong
```

```sh
cd build
cp ../secrets.sed.example ../secrets.sed   # fill in every token
./nix-run.sh mon                           # -> build/.work/<device>/
```

`build.sh` downloads a pinned ImageBuilder, renders the overlay
(`build/vars.sed`, then `secrets.sed`), fetches `authorized_keys` from the
`pubkeys` repo and runs `make image`. The images contain baked credentials.

The ImageBuilder tarball is pinned by checksum; the release package feeds are
not. They are fetched at build time and change in place, so each device's
resolved package set is recorded under `build/manifests/`, and a build that
resolves different versions fails until the diff is reviewed and recorded.

## Flashing

- `sysupgrade` with `*-squashfs-sysupgrade.bin` from `build/.work/<device>/targets/`;
  `-n` makes the baked config authoritative. Host keys come from
  `secrets/<device>/`, so `known_hosts` stays valid; the root password is only for
  LuCI and the console.
- `-n` also discards `/etc/ssl` and `/etc/uhttpd.*`; a build seeds a certificate
  into the image, so the box serves the real one from first boot instead of the
  self-signed placeholder.
- mon's first install needs the factory image or u-boot recovery, not
  `sysupgrade`.

## Recipes

The image ships a recipe for problems that come up: `jail-pairing on|off` opens
the jail so a WPS device can pair, and closes it again once the device is
registered; cron closes it at 04:35 either way.
