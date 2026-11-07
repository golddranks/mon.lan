# mon.lan

OpenWrt images for a two-AP home network; all configuration is baked into the
image through the ImageBuilder's `FILES` overlay.

| Device | Hardware                 | Target / profile                       | Role       |
| ------ | ------------------------ | -------------------------------------- | ---------- |
| `mon`  | GL.iNet MT6000 (Flint 2) | `mediatek/filogic`, `glinet_gl-mt6000` | router, AP |
| `ban`  | TP-Link Archer C7 v2     | `ath79/generic`, `tplink_archer-c7-v2` | dumb AP    |

## mon

- **WAN** DHCPv4 + DHCPv6-PD (/56), with the DHCPv6 DUID fixed — otherwise
  every `sysupgrade -n` shows the ISP a new client. **LAN** is IPv6-only: no
  IPv4, no DHCPv4; the GUA prefix is set explicitly in `/etc/config/network`
  (J:COM delegates prefixes it does not route), plus ULA `fd42:6d6f:6e00::/48`
  for stable names. `/root/recipes/set-lan-prefix` rewrites it when it stops
  answering.
- **NAT64 + DNS64**: unbound synthesises AAAA in `64:ff9b::/96` and Jool
  translates to the WAN IPv4; `ra_pref64` lets clients build a CLAT (464XLAT).
- Jool's `pool4` is empty, so translation uses the WAN address on ports
  `61001-65535` (4535 per protocol). Configured pools name an address DHCP can
  change; stale rows killed IPv4 here silently while IPv6 stayed fine.
- **DDNS** (Gandi): A + AAAA for `bitwarden`, `syncthing`, `webshare`, `cafe`;
  AAAA only for `bead` and `llm`. The AAAA is the LAN /64 plus the host id
  odhcpd keeps for the name (`/usr/lib/ddns/lan_suffix.sh`). Apex and
  `jcom.drasa.eu` are not published.
- Inbound TCP 22/80/443 is forwarded to LAN hosts (no NAT66) while the router's
  own input stays closed; IPv4 80/443 terminates on nginx, proxying to cafe.
- `mon.lan`, `ban.lan`, `mon.drasa.eu`, `ban.drasa.eu`, `bead.lan`,
  `bead.drasa.eu` and `llm.drasa.eu` (bead's LLM vhost): static ULA entries,
  the `drasa.eu` ones published publicly for the certificate.
- **Jail**: `SkeletorJail` on radio0 (2.4 GHz) over `br-iot`, `10.10.1.1/24`,
  DHCPv4 and masquerade to the WAN, no IPv6 - for devices that cannot use the
  IPv6-only LAN.
- **Wireless**: one SSID on both bands (ch 1 / 36, `JP`, WPA2-PSK from
  `secrets.sed`), 802.11r (`mobility_domain cc66`, `ft_psk_generate_local`) and
  802.11k/v, which need `wpad-mbedtls`; `usteer` steers over IPv6.
- **LuCI** on nginx via uwsgi: `_lan` is a LAN-only default_server with a
  self-signed cert, `mon.drasa.eu` carries Let's Encrypt issued over DNS-01
  (Gandi API), so nothing is opened inbound. IPv4 :80/:443 are nginx's `stream`
  proxy, routing 443 by SNI to cafe so cafe keeps its own certificates.
- **Diagnostics**: `netdiag` checks the invariants and exits non-zero on
  failure; `mon-watch` runs it every 10 min and mails only when the failing set
  changes (`/root/mon-watch.expected` silences known temporary states and is not
  in the image); `mon-weekly` mails netdiag, addressing, routes, Jool counters
  and the last 200 kernel log lines; `mon-send` delivers via `msmtp`
  (recipient baked from `secrets.sed`, credentials `/etc/msmtprc`), appending failures to `/root/mon-notify.log`.

## ban

A dumb AP: it bridges, nothing else.

- `br-lan` over `eth1`, the untagged LAN CPU port of the swconfig switch; all
  five ports in one VLAN, so the uplink can use any of them.
- Static ULA `fd42:6d6f:6e00::2/64`; LuCI listens only there (`99-uhttpd-ula`).
  SLAAC still gives it a GUA and a default route (`accept_ra=2`, forwarding is
  on), which is what the netdiag datapath probe runs from, and `rc.local` sets an
  `ip token` so future GUAs end in `::2`. No `dnsmasq`/`odhcpd`: mon is the only
  DHCP, RA and DNS server.
- Stock `uhttpd` + `luci-ssl` with the cert from `secrets/ban/uhttpd.crt`; SSH
  key-only; time from mon. Offset channels (2.4 GHz: 6, 5 GHz: 52 — DFS).

## Layout and building

```
build/build.sh          build one device
build/packages/         packages to bake in ('-name' removes a default)
build/vars.sed          values substituted into the overlay (@ULA@, @LAN_PREFIX@, @FT_MDID@)
build/flake.nix         pinned lima (qemu x86_64) environment, ./nix-run.sh
image/mon/  image/ban/  rootfs overlays, with @TOKEN@ placeholders
LEARNINGS.md            assumptions that turned out wrong
```

```sh
cd build
cp ../secrets.sed.example ../secrets.sed   # fill in every token
./nix-run.sh mon                           # -> build/.work/<device>/
```

`build.sh` pins the release and ImageBuilder checksum, verifies the tarball,
renders the overlay (`build/vars.sed`, then `secrets.sed`), fetches
`authorized_keys` from the `pubkeys` repo and runs `make image`. The images
contain baked credentials.

## Flashing

- `sysupgrade` with `*-squashfs-sysupgrade.bin` from `build/.work/<device>/targets/`;
  `-n` makes the baked config authoritative. Host keys come from
  `secrets/<device>/`, so `known_hosts` stays valid; the root password is only for
  LuCI and the console.
- `-n` also discards `/etc/acme`, so every flash would issue a new Let's
  Encrypt certificate, and the limit is five per 168 hours for the same names.
  `build.sh` therefore restores `secrets/<device>/acme.tar` when it exists;
  refresh it after a renewal:
  `ssh root@mon 'cd / && tar -czf - etc/acme etc/ssl/nginx' > secrets/mon/acme.tar`
- mon's first install needs the factory image or u-boot recovery: a non-empty
  `/etc/config/network` and `/etc/config/system` make `/bin/config_generate`
  exit early, and `/etc/uci-defaults/*` runs once.

## Recipes

`/root/recipes/` holds small scripts for problems that come up. They ship with
the image and do one thing each. The first is `set-lan-prefix <prefix>/64`,
which sets the LAN GUA and its source route and reloads odhcpd; run it when
`netdiag` reports `lan-sourced egress` failing.

## Not yet implemented

- **The jail reaches no further than mon's 2.4 GHz radio.** ban cannot carry it
  without a VLAN across the uplink cable, and WPS push-button pairing (for the
  A/C and doorbell, which have no usable keyboard) is not enabled.
- **WireGuard, in its final form.** The throwaway server was removed. It needed
  an init script because netifd here starts before `wireguard-tools` exists, so
  `proto wireguard` is unknown and `ifup` returns NO_DEVICE; baking the packages
  into the image should retire that workaround, and peers still need a
  manageable way to be added.
- **Smarter monitoring.** The checks are hand-written labels; a pass over the
  state they collect (netdiag output, logread, Jool counters) could catch
  combinations nobody thought to write a check for.
