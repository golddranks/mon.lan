# Learnings

Assumptions that looked obvious and turned out to be wrong. Each entry is the
assumption, what actually happens, and where it bit. Append as new ones surface;
prefer a line of fact over a paragraph of reasoning.

## netifd and addressing

- **A delegation means a prefix, not a route.** J:COM hands out a healthy
  `/56` and routes none of it; LAN GUAs built from it are dead while every lease
  and netifd check stays green.
- **Routing changes under you.** The same prefix answered a LAN-sourced ping
  early in a session and did not answer two hours later. Never store "this
  prefix works"; re-probe it.
- **netifd only installs `default from <prefix>` for prefixes it assigned** out
  of a delegation. A prefix that is set explicitly needs its own `route6`
  section, and that section needs a `gateway`: without one you get an on-link
  route that does nothing.
- **The route's `gateway` is the ISP's link-local** (`fe80::217:10ff:feaa:caab`),
  not an address this repo controls. `set-lan-prefix` reuses it from uci, so
  different ISP equipment needs the config edited, not the recipe run.
- **`ip6assign '0'` disables assignment** (netifd only accepts 48–64). Without
  it, a delegated-but-unrouted /64 lands on br-lan next to the configured one
  and gets advertised to clients.
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
- **One definition, or it rots.** The ULA and the LAN /64 are one line each
  in `build/vars.sed`; the overlay carries `@ULA@`/`@LAN_PREFIX@` and `build.sh`
  substitutes them the same way it substitutes secrets, refusing to ship a
  leftover `@TOKEN@`. Scripts derive the same values from uci instead.
  Consequence: files under `image/` are templates - the copy to put on a box is
  the rendered one in `build/.work/<device>/files/`.
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

## DDNS

- **`_aaaa` is the LAN prefix plus the host id**, so an expectation derived from
  the delegation's stem asserts the wrong thing (and would call a correct record
  wrong).
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
