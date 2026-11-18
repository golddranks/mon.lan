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
  templates, and the copies that reach a box are the rendered ones.
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
- **The bind was never the security boundary.** The `wan` zone rejects input,
  and `checkup` asks from outside whether 22/80/443 are refused there. Binding
  bought nothing and cost the three entries above.

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

## Names and resolution

- **Rebind protection discards a public record that points into private space.**
  The zone publishes mon's and ban's ULAs, and both resolvers refuse them unless
  told otherwise: unbound needs `private-domain`, dnsmasq `rebind-domain-ok`.
- **A `.lan` name served from odhcpd's hosts file disappears at every boot.**
  That file lives in `/tmp`, and the name returns only when its host renews -
  minutes for one host, longer for another. `cafe.lan` and `bead.lan` are
  written down in dnsmasq for that reason.

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
- **`scp` splits the destination on the first colon**, so an IPv6 address has to
  be bracketed: `root@[fd42:6d6f:6e00::1]:/tmp/x`.
  Unbracketed, scp reports `connection lost`, which reads like the link dropping.

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

## NixOS updates

- **A finished channel build is not the channel yet.** Hydra's `nixos.channel`
  job producing its output only starts the clock; the channel is the directory
  `releases.nixos.org` then publishes under the output's own name
  (`nixos-26.05.<n>.<rev>`), and its mtime is that moment. Measured lags: 4 h
  56 m, 16 h 13 m, 22 h 44 m, 26 h 49 m, 28 h 50 m. Half the builds in the
  same window had no directory at all - superseded before publishing - so a
  list of Hydra builds is not a list of channel revisions.
- **The channel tarball is not the branch.** `releases.nixos.org` writes a
  build's directory about four minutes before `nixos-channel-bot` advances
  `nixos-XX.YY` (4 m 08 s, 4 m 08 s, 4 m 20 s over three builds). A flake
  resolves the branch and never the tarball, so the push is the earliest moment
  a lock can carry the revision, and the directory's mtime is the `nix-channel`
  clock. `checkup` dates by the push, read from the
  repository's activity API rather than from hydra and the release directory.
- **The lock follows `nixos-26.05`, which moves at publication, so a quiet run
  means the branch has not moved.** The run at 11-16 07:16 JST committed only a
  `nixpkgs-unstable` bump although Hydra had finished `b349185` five hours
  earlier; `nixos-26.05` moved to that revision after that run.
- **A host can never be at the lock's pin.** The pin is whatever was newest when
  the Action ran, and the hosts build whatever the lock says at 04:40 JST, so a
  pin that lands at 10:18 is only reachable at the next 04:40 - a day after it
  became the bar. "Up to date" has to mean the newest build published
  `NIXOS_PIN_GRACE_DAYS` ago.
- **Publication to a host running it reaches 36 h, against a 48 h grace.** The
  Action's queue delay is 3 h 48 m to 7 h 16 m past its scheduled minute, which
  eats into the day between publication and the next run and leaves ~32 h. What
  exceeds the grace is a dropped Action run (60 h), not the timing.
- **`26.05.20261113.f1e5c35` dates itself twice, and the day is the lossy one.**
  The middle field is a UTC date, so a 2.4-day gap reads as 2 or 3 depending on
  the hour, and `date -d` on a bare date reads it in JST. The revision is exact
  and is what the channel list can be matched against.

## Method

- **busybox lacks `df -x` and `timeout`; coreutils' applets replace them.**
  checkup had filtered mountpoints by hand instead of asking df, and capped ssh
  with a background killer whose comment was about leaked descriptors.
  `coreutils-df` takes over `/bin/df` as a link to `/usr/libexec/df-coreutils`,
  and `coreutils-timeout` adds `/usr/bin/timeout`; both are per-applet packages,
  so the image pays for two binaries rather than a coreutils install.
- **`jq` is the JSON parser the image was missing.** jsonfilter selects a path
  but cannot compare array elements, so every query - the branch activity, the
  endoflife.date list, the lock's ref - was `tr`/`sed` over the raw text. It is
  one package, and the parses are now the queries they were meant to be.
- **`acme-common` decides renew-versus-issue by its store in `/etc/acme`, not by
  the certificate being served.** `sysupgrade -n` wipes both, so an image with a
  certificate but no store issues again on first boot; a day of flashing spent
  the 5 certificates per 168 h Let's Encrypt allows and left the box on the
  self-signed placeholder until the window rolled over. The build now bakes the
  store beside the certificate, so a flash presents what the last build seeded.
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
- **At boot the clock is the image's build time.** ntpd validates it a few
  seconds after the WAN comes up, and until then every timestamp - a mail's
  Date header, a syslog line - says the build date. The boot mail waits for the
  ntp `stratum` hotplug for that reason.
- **A LAN client reads mon's reboot as the link going away.** cafe's dhcpcd
  deleted its GUA and routes 14 s after mon stopped answering, re-solicited
  into mon's boot window, and accepted a REPLY that carried timers but no
  address; it then waits T1 before asking again - 1350 s in the observed case,
  not the `expire in 43200` the log also prints. So `cafe.drasa.eu` is
  IPv6-dead for roughly twenty minutes after every flash.
- **`/tmp/dhcp.leases` is empty on every boot.** It is rebuilt from renewals,
  and a device renews at half its lease, so an absent lease proves nothing until
  one whole window has passed. The jail's check reads the silence off the lease
  itself - `leasetime - left` - and only judges a device once mon has been up
  for the 24 h it tolerates.
