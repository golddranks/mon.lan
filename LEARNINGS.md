# Learnings

Assumptions that looked obvious and turned out to be wrong. Each entry is the
assumption, what actually happens, and where it bit. Append as new ones surface;
prefer a line of fact over a paragraph of reasoning.

## netifd and addressing

- **A delegation means a prefix, not a route.** J:COM hands out a healthy
  `/56` and routes none of it; LAN GUAs built from it are dead while every
  lease and netifd check stays green. What that caught was a prefix that had
  stopped being routed: on 2026-11-10 the reverse also held - the delegated
  `/56` routed and two provisioned prefixes did not. Probe the prefix; the
  delegation alone says nothing (see J:COM specifics).
- **Routing changes under you.** The same prefix answered a LAN-sourced ping
  early in a session and did not answer two hours later. Never store "this
  prefix works"; re-probe it.
- **netifd only installs `default from <prefix>` for prefixes it assigned** out
  of a delegation. A hand-set prefix needs its own `route6` section with a
  `gateway`; without one you get an on-link route that does nothing.
- **`ip6assign '0'` disables assignment** (netifd only accepts 48-64). The LAN
  uses `64`, so netifd puts the first /64 of the delegation on br-lan.
- **`uci show` prints a list as `'a' 'b'` and an option as `'a b'`**, both on one
  line. A `key='value'` regex over it silently misses lists.
- **`uci set foo.bar='a b'` stores one option, not a list.** For `ip6addr`
  netifd splits it anyway (it works), but the image config declares a list, and
  the two print differently, which made a healthy config look broken.
- **`ip token` is not retroactive.** Existing SLAAC addresses keep their EUI-64
  host id until their RA lifetime expires; the token only shapes addresses
  generated afterwards.
- **The ULA is a hand-picked mnemonic, not RFC 4193.** `fd42:6d6f:6e00` is
  `fd42` + "mon" + `00`; nothing generated or verified it. Acceptable on one
  private network; re-check before peering with another site.
- **One definition, or it rots.** The ULA is one line in `build/vars.sed`; the
  overlay carries `@ULA@` and `build.sh` substitutes it the same way it
  substitutes secrets, refusing to ship a leftover `@TOKEN@`. Scripts derive
  the same value from uci instead. Consequence: files under `image/` are
  templates - the copy to put on a box is the rendered one in
  `build/.work/<device>/files/`.
- **Names are not values.** A name somebody chose (a domain, an SSID, a host id)
  is its own best spelling and stays literal. An arbitrary value - an address, a
  prefix, an opaque id like the 802.11r mobility domain - is a candidate for a
  build variable, even when it is short enough to read. Only if it repeats: a
  value that occurs once gains nothing from a name.

## SSH and dropbear

- **`Interface 'lan'` binds addresses, not the interface**: one `-p <addr>:22`
  per address at start, so a GUA change leaves SSH on a deleted address.
- **`DirectInterface` must name the logical interface** (`lan`), not the device
  (`br-lan`); with a device name the init cannot resolve it and dropbear is never
  started, silently.
- **Any `network reload` can kill SSH.** procd runs `/etc/init.d/dropbear
reload` on `interface.*`; `dropbear_instance()` returns 1 while
  `network_is_up lan` is false during the teardown transient, and no later event
  restarts the instance. The box is up, the web UI is up, port 22 is refused.
- **Recovery without a shell: LuCI → System → Startup → dropbear → Restart.**
  It works because `lan` is up again by the time you click it.
- **authorized_keys options are ignored for root.** `command=` in root's
  per-user file and in the global `/etc/dropbear/authorized_keys` was ignored -
  the client's command ran - while the same option worked for a non-root user.
  A privileged key cannot be scoped that way; scope an unprivileged account and
  have root pick up what it stages.
- **Deleting a host key file does not stop dropbear offering it.** OpenWrt's
  `/etc/init.d/dropbear` generates any of `ed25519 ecdsa rsa` whose file is
  missing, on every start, and with no `-r` dropbear loads every default key in
  `/etc/dropbear`. Only `list keyfile` in `/etc/config/dropbear` binds the
  server to named keys. ECDSA is not compiled into this build, so its
  generation fails and the type simply never exists.
- **`/etc/init.d/dropbear restart` can silently no-op.** We found two live
  servers with different argv and an unchanged pid file after "restarting" it.
  Verify with `ps`, not with the init script's exit status.
- **The bind was never the security boundary.** The `wan` zone rejects input and
  `netdiag` asserts 22/80/443 are not accepted there. Binding bought nothing and
  cost the three entries above.

## J:COM specifics

- **The modem's IPv6 WAN address is a `/128` out of the ISP's /64**, not a
  segment routed to us; hosts inside that /64 are not ours to address.
- **A network restart can change the IPv4 lease.** Tying the whole NAT64 setup
  to the old address then breaks v4 egress while v6 keeps working.
- **Which prefixes the line routes is provisioning, not delegation.** On
  2026-11-10 every prefix mon had held answered nothing (5 probes each), the
  current delegation `54e:a100::/56` answered, and the two prefixes from the
  cable modem's routing-mode experiment answered 5/5 six days after the modem
  stopped using them. Routing outlives the device that held the prefix and
  does not follow DHCPv6-PD.
- **Prefix timeline.** First mention in the session log, anchored to the
  nearest preceding timestamp there, so approximate. All `2405:1200:...`.

  | first seen       | prefix                                         | role                           |
  | ---------------- | ---------------------------------------------- | ------------------------------ |
  | 2026-06-30       | `542:1800`                                     | previous router, not this line |
  | 2026-10-20 06:46 | `542:5500`                                     | LAN                            |
  | 2026-10-20 08:08 | `542:5f00`                                     | second prefix that day         |
  | 2026-11-02 17:31 | `54b:3800`                                     |                                |
  | 2026-11-02 19:28 | `54b:4500`                                     | LAN until 2026-11-10           |
  | 2026-11-02 19:28 | `54b:6e00`, `54b:8600`, `54b:8800`, `54b:d100` | later delegations              |
  | 2026-11-03 22:13 | `54c:800`, `54c:b00`                           | cable modem, routing mode      |
  | 2026-11-03 23:43 | `54c:1600/1700/1900`                           | probing                        |
  | 2026-11-04 01:00 | `54c:2700/2800/2a00/2b00`                      | probing                        |
  | 2026-11-04 02:52 | `54c:3300/3600/3700/3800`                      | DUID/release experiments       |
  | 2026-11-04 11:33 | `54c:7100`                                     |                                |
  | 2026-11-06 17:23 | `54d:f100`                                     |                                |
  | 2026-11-06 19:26 | `54e:1900`, `54e:3c00`                         |                                |
  | 2026-11-07 18:20 | `54e:a100`                                     | delegation, current            |

  `54e:a100` was already the delegation on 2026-11-07 while the LAN stayed on
  `54b:4500`, which still routed then. Nothing broke until that route died, so
  a stale LAN prefix is invisible to every check except a reachability probe.
  Since 2026-11-10 the LAN takes the first /64 of the delegation, so a new
  delegation is adopted without an operator step.

- **The PD lease is 7 days, but the first OFFER says 300 s.** The OFFER carries
  pltime 270 / vltime 300; the REPLY carries 544320 / 604800 (preferred 90 %,
  T1 3.5 d, T2 6.1 d). The binding sticks while the DUID is stable; `release`
  or a DUID change yields a new `/56` at once. Captured 2026-11-04.

## DDNS

- **`_aaaa` is the LAN /64 plus the host id**, and the LAN /64 is the first /64
  of the delegation, so the delegation's stem is the right expectation while
  `ip6hint` stays 0.
- **"Update successful" can mean nothing was sent** (the dry-run path prints the
  same line), and Gandi's authoritative NSes disagree for minutes after a change,
  so a check that picks one NS at random alternates PASS/FAIL.
- **The cycle is 600 s.** A prefix change is invisible to DNS until then.

## NAT64 / Jool

- **`JSTAT_POOL4_MISMATCH` climbs continuously** with an empty pool4 and working
  IPv4 egress. On its own it is not evidence of a broken datapath.

## Hardware

- **Board labels are not a port map.** Confirm `eth1` / `lan1..lan5` on the
  running mon before trusting `board.d/02_network`.
- **A radio without its full sysfs path gets hijacked.** ban's radios need
  `pci0000:00/0000:00:00.0` and `platform/ahb/18100000.wmac`; with a bare
  `radio0`/`radio1` a duplicate takes the phy over.

## Wireless

- **Offering both WPA2 and WPA3 keeps clients on WPA2, silently.** With
  `sae-mixed` the Mac stayed on `FT_PSK` and reported nothing; it negotiated
  `FT_SAE` only once the WPA2 BSS was gone. A mixed SSID says nothing about
  which clients support SAE.
- **One BSS can carry both kinds.** The jail is `sae-mixed`: the doorbell and
  Switch 2 join it with SAE (`auth_alg=sae` in hostapd's log) and Switch 1 and
  the scale join the same BSS with WPA2 (`auth_alg=open`). The main SSID is pure
  `sae`.
- **A client's first association is not its final answer.** Switch 2 connected
  with `auth_alg=open` for a while and only later negotiated SAE on the same
  BSS; the doorbell looked WPA2-only because it had not retried during the short
  window the jail was SAE. Wait for the client, or read `auth_alg=`, before
  concluding anything about it.
- **WPS is a switch in the BSS config, not a window.** Without `wps_pushbutton`
  hostapd advertises no WPS at all; with it, the beacon carries the WSC element
  and `config_methods` holds `push_button` alone (no PIN to guess). The window
  itself is a control-interface command on top of that.
- **A wireless config change restarts only the BSS that changed.** One hostapd
  process and one global socket serve every phy, so it looks all-or-nothing, but
  netifd restarts the network interface that owns the changed BSS: the jail went
  `AP-DISABLED`, `Interface 'iot' is now down`, `Add bss phy0-ap1 on phy phy0`,
  while `phy0-ap0` and `phy1-ap0` stayed `ENABLED` with their stations.
- **`uci set` records nothing when the value is unchanged**, so `uci changes`
  after setting is the cheap "does a reload have to happen" test.

## The jail

- **Client isolation is per BSS, and the firewall cannot help on a bridge.**
  Traffic between two stations on the same bridge is switched, not routed, so the
  zone's forward policy never sees it; `option isolate '1'` drops those frames at
  the AP. A wired port in the same bridge would need bridge-port isolation
  instead.
- **A device can require the gateway to answer ping.** The doorbell sent
  nothing but echo requests to 10.10.1.1 and retried forever; a zone that
  rejects input reads to it as "cannot find the router". One echo-request rule
  and it went on to its NTP and cloud lookups.
- **A device with IPv6 is not a device that uses it.** Switch 2 autoconfigured a
  GUA and a ULA from the RAs, ran DAD on both, then never sent a packet from
  either: its network test wants a DHCPv4 lease, and without one it throws the
  autoconf away and DISCOVERs again every 30 s. The jail exists for that class of
  device.

## Builds

- **The overlay cannot contain symlinks.** Lima mounts `$HOME` over sshfs, and
  the guest cannot `readlink` anything in it (`Operation not permitted`), so
  `cp -a` of the overlay dies on the first symlink. Enable a service with
  uci-defaults instead of shipping `etc/rc.d`.
- **The ImageBuilder checksum pins the target payload, not the package set.**
  The architecture feeds (`base`, `luci`, `packages`) are fetched at build time
  and updated in place: `luci` moved from `26.304.26398` to `26.312.33065` and
  `uhttpd` from `2026.08.24` to `2026.11.05` between two builds a day apart,
  with the same package count. `build/manifests/<device>.manifest` records what
  was accepted, so the next build reports the difference instead of shipping it
  silently.

## Unprivileged probes

- **busybox ping is raw-socket only.** It refuses non-root even when
  `net.ipv4.ping_group_range` covers the user's gid; iputils' ping uses ICMP
  datagram sockets and works with the range.
- **hato's `ping6` is inetutils, not iputils.** `ping6 -c 2 -W 3` exits 64
  there, while `ping -6 -c 2 -w 5` works, so a probe copied from mon's busybox
  `ping6` fails on hato for no network reason.
- **IPv6 literals need brackets in URLs and in `-connect`.** `http://fd42::1/`
  is not a URL and `-connect fd42::1:443` is not a socket; curl answers `000`,
  which reads exactly like "nothing is listening".

## WireGuard

- **A public key belongs to one interface.** The peer convergence treats a key
  found on another interface as moved and recreates it on the current one, so a
  keypair shared between `lan_vpn` and `jail_vpn` lands wherever the last TSV
  read puts it and the other line silently does nothing. A host joining two
  interfaces needs two keypairs.
- **`uci commit network` does not apply peers, and `ifup` is asynchronous.**
  `ubus call network reload` does not either; only `ifup <iface>` reconfigures,
  and `wg show` straight afterwards still lists the old peers for a few seconds.
- **A client's routes come from its own `allowedIPs`.** A probe peer restricted
  to `8.8.8.8/32` cannot reach mon's DNS even with the tunnel up: anything
  outside that list is not routed into the interface at all.

## Cron

- **busybox crond cannot be quiet.** Every job start is logged at `err`
  (`USER root pid N cmd ...`) and `-l` cannot hide it: 0-4 add debug lines
  (`wakeup`, `file`, `job:`, `child running`), 5-8 print the same job line. A
  per-minute job is therefore ~144 KB/day of log in a 64 KiB ring. Reaching for
  a procd loop instead costs nothing.

## Method

- **`sysupgrade -n` throws away `/etc/acme`, so every flash is a new issuance.**
  Let's Encrypt allows 5 certificates per 168 h for the same set of names, so a
  day of flashing left the box serving the image's self-signed placeholder until
  the window rolled over. `acme renew` runs hourly and recovers by itself.
- **A hotplug hook is not self-healing.** The adaptive `95-pin-lan` only fired on
  `wan6 ifup`, so it was neither sufficient nor simple. A user-run recipe plus a
  checker that measures beats code that guesses.
- **Test a destructive recipe on the box with the current value first.** The
  idempotent re-run caught a `stem` bug that would have deleted the LAN GUA on
  first real use.
- **busybox ash: `${1:?msg}` does not abort the script** (it only kills the
  substitution's subshell). Guard arguments with `case`.
- **`${1%/64}` leaves the trailing `::`.** Strip trailing colons before building
  `::1/64`, or you get `::::1`.
- **`scp` to mon needs `-O`**; `ssh 'cat > file' < local` avoids the question
  entirely.
- **`/tmp/dhcp.leases` is empty on every boot.** It is rebuilt from renewals
  and dnsmasq renews at half a 12 h lease, so an absent lease proves nothing
  until 6 h of renewals have passed; the IoT liveness check waits 7 h before it
  asserts anything, instead of calling every device dead after a flash.
