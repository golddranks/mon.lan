# mon.lan

OpenWrt images for a two-AP home network; all configuration is baked into the
image through the ImageBuilder's `FILES` overlay.

| Device | Hardware                 | Target / profile                       | Role       |
| ------ | ------------------------ | -------------------------------------- | ---------- |
| `mon`  | GL.iNet MT6000 (Flint 2) | `mediatek/filogic`, `glinet_gl-mt6000` | router, AP |
| `ban`  | TP-Link Archer C7 v2     | `ath79/generic`, `tplink_archer-c7-v2` | dumb AP    |

```
J:COM ── eth1 [mon] br-lan ══════ cable ══════ br-lan [ban] ~~ SSID "Skeletor"
```

## mon

- **WAN** DHCPv4 + DHCPv6-PD (/56), with the DHCPv6 DUID pinned — otherwise
  every `sysupgrade -n` shows the ISP a new client. **LAN** is IPv6-only: no
  IPv4, no DHCPv4; SLAAC and DHCPv6 out of the delegated /56, plus ULA
  `fd42:6d6f:6e00::/48` for stable names.
- **NAT64 + DNS64**: unbound synthesises AAAA in `64:ff9b::/96` and Jool
  translates to the WAN IPv4; `ra_pref64` lets clients build a CLAT (464XLAT).
- Jool's `pool4` is empty, so translation uses the WAN address on ports
  `61001-65535` (4535 per protocol). Configured pools name an address DHCP can
  change; stale rows killed IPv4 here silently while IPv6 stayed fine.
- **DDNS** (Gandi): A + AAAA for `bitwarden`, `syncthing`, `webshare`, `cafe`.
  odhcpd pins cafe's host id, so its AAAA is the delegated /64 plus `::cafe`
  (`/usr/lib/ddns/lan_suffix.sh`). Apex and `jcom.drasa.eu` are not published.
- Inbound TCP 22/80/443 is forwarded to LAN hosts (no NAT66) while the router's
  own input stays closed; IPv4 80/443 terminates on nginx, proxying to cafe.
- `mon.lan`, `ban.lan`, `mon.drasa.eu`, `ban.drasa.eu`: static ULA entries, the
  `drasa.eu` ones also published publicly so the certificate has a real domain.
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
- Static ULA `fd42:6d6f:6e00::2/64`, no default route — deliberately not a GUA,
  since mon forwards inbound 22/80/443. `accept_ra=2` still lets the netdiag
  datapath probe here learn a route. No `dnsmasq`/`odhcpd`: mon is the only
  DHCP, RA and DNS server.
- Stock `uhttpd` + `luci-ssl` with the cert from `secrets/ban/uhttpd.crt`; SSH
  key-only; time from mon. Offset channels (2.4 GHz: 6, 5 GHz: 52 — DFS).

## Layout and building

```
build/build.sh          build one device
build/packages/         packages to bake in ('-name' removes a default)
build/flake.nix         pinned lima (qemu x86_64) environment, ./nix-run.sh
image/mon/  image/ban/  rootfs overlays
```

```sh
cd build
cp ../secrets.sed.example ../secrets.sed   # fill in every token
./nix-run.sh mon                           # -> build/.work/<device>/
```

`build.sh` pins the release and ImageBuilder checksum, verifies the tarball,
applies `secrets.sed` to the overlay, fetches `authorized_keys` from the
`pubkeys` repo and runs `make image`. The images contain baked credentials.

## Flashing

- `sysupgrade` with `*-squashfs-sysupgrade.bin` from `build/.work/<device>/targets/`;
  `/etc/config` survives by default, `-n` makes the baked config authoritative.
- mon's first install from GL.iNet firmware needs the factory image or u-boot
  recovery. `/bin/config_generate` exits early when `/etc/config/network` and
  `/etc/config/system` are non-empty, so detection never overwrites the baked
  config; `/etc/uci-defaults/*` runs once and `firstboot` keeps the config.

## Not yet implemented

IPv4-only devices (Switch, A/C, doorbell) need a second SSID on a `br-iot` bridge
with NAT, no 802.11r, and WPS push-button pairing (`wps_pushbutton '1'`, `hostapd_cli
-i <iface> wps_pbc`); the build already carries what that needs.

## Notes

- Confirm `eth1` / `lan1..lan5` on the running mon before trusting the port map.
- ban's radios need their **full** sysfs path (`pci0000:00/0000:00:00.0`,
  `platform/ahb/18100000.wmac`); a duplicate radio otherwise takes the phy over.
- SSH is key-only (`authorized_keys` from `pubkeys`); the root password is for
  LuCI and console. Host keys from `secrets/<device>/` keep `known_hosts` valid.
