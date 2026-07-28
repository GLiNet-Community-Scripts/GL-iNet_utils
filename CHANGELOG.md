# Changelog

All notable changes to the GL.iNet Utilities toolkit. Newest first. Versions
match the `# Version:` line in the script — `YYYY-MM-DD`, or `YYYY-MM-DD_HH:MM`
for multiple releases on the same day.

## 2026-07-28
- Fixed: text no longer loses its last character in Termius. Lines that mix a
  status glyph with colour were being clipped by one cell per coloured section,
  so "Operation completed successfully" rendered as "successfull" and the
  two-column status row lost a character from BOTH halves. Measured rather than
  guessed: the terminal drops the final cell of each coloured section on any
  line carrying a glyph it paints wider than it reserves space for, so each
  section now ends with a spare space for it to take. A pixel-level overhang
  remains on some glyphs; that is a font metric and cannot be corrected from
  here.
- Fixed: the display-mode preview's Help row sat a column left of the numbered
  items in Termius, and the same row was misaligned in the browser terminal.
- Fixed: the Web-UI Terminal button did not appear on firmware 4.9.x. The button
  is injected next to the reboot icon in the admin panel header, but it worked
  out WHERE to put itself from the help icon beside it - and from 4.8.6 onward
  that icon moved into a support dropdown, so the button was inserted outside
  the toolbar where nothing could show it. It now positions itself relative to
  the reboot icon alone, which has stayed put across every firmware checked
  (4.3.25 through OpenWrt 25). Verified on both an affected and an unaffected
  firmware so the older ones behave exactly as before.
- Fixed: the Web-UI Terminal opened too small - 130x29, below the 101x33 some
  screens need, so the toolkit warned about window size inside its own web
  terminal. It now opens at the standard 110x33, with the font pinned so the
  size is consistent rather than following whatever the browser defaults to.
  Resizing, maximising and minimising all still work.
- Fixed: status symbols were spaced wrongly in the browser terminal. Ticks,
  crosses and the padlock in the Remote LAN Access table were padded on the
  assumption that the browser draws every symbol one column wide; it draws
  several of them two columns wide, exactly as Termius does. Messages, menu
  rows and that table now line up there.
- Added: the Web-UI Terminal screen shows the direct URL and port, so the
  terminal is reachable even if the panel button is missing on some firmware.
- Fixed: Termius was reported as "macOS/Linux" in Toolkit Management while the
  Display Settings page correctly identified it. Both now agree.

## 2026-07-27
- Fixed: package installation on OpenWrt 25, which replaced opkg with apk. All
  package operations now go through a small abstraction that picks whichever
  manager the router has, so installing, removing and checking work on both.
  This is what stopped zram swap installing on OpenWrt 25 - nothing about zram
  itself was wrong. This also covers the two places that bootstrap themselves:
  the coreutils-stty install on first run (without which the display silently
  drops to Compatible mode) and the post-upgrade package restoration hook.
- Fixed: startup no longer paints the splash and then visibly shifts it, and
  output from the previous run no longer appears above it. Both had the same
  cause - the splash was drawn before the window was widened. Clearing the
  screen does not clear the scrollback, and widening a window pulls
  scrolled-off lines back into view, so the remnants arrived after the clear
  rather than before it. Nothing is drawn now until the window has settled at
  its final size.
- Fixed: the minimum window height was one row short. Hardware Information
  page 1 needs 33 rows, not 32 - the blank line above the header was missed
  when it was measured.
- Changed: while the toolkit waits for the terminal to apply a resize, it says
  so with a progress message instead of sitting on a blank screen, which read
  as a hang on terminals that ignore the request. The message only appears once
  the wait is long enough to notice; terminals that resize promptly still show
  nothing.
- Changed: the window-size prompt now confirms what happened. Rechecking after
  a successful resize says so, and continuing at a small size acknowledges the
  choice, rather than either clearing straight to the splash with no output.
- Fixed: a stray combining character in the guest-limits status made one of the
  two arrows render as a mangled mark. Arrow style is now consistent across
  user-facing text.
- Fixed: Ookla Speedtest now explains itself instead of failing late on MIPS
  routers. Ookla ships its own binary and does not build one for MIPS, so the
  install could never succeed there - but it only failed after downloading,
  with nothing saying why. It now says so before starting and points at
  LibreSpeed and iperf3, which both work.
- Fixed: the Full-mode samples on the display-mode preview were spaced for a
  typical terminal rather than the one in use, so they rendered short in
  Termius. They now follow the same per-terminal spacing as the rest of the
  toolkit.
- Fixed: the cooldown pause in the CPU thermal stress test could be skipped
  entirely on a build without busybox's `usleep`, making the "after cooling"
  temperature a duplicate of the peak reading rather than a real measurement.
  It now falls back to a plain sleep of the same length, as the other pauses
  already did.
- Fixed: the terminal-size check no longer warns about a window that is already
  being resized. It asks the terminal to resize, then waits up to 5 seconds for
  that to take effect before judging, instead of reading the old size
  immediately. Terminals known to ignore the request - Termius - are not asked
  at all, so their advice appears straight away rather than after a wait for
  something that was never going to happen.

## 2026-07-26
- Fixed: masquerade and remote-access changes are now refused outright when the
  VPN's firewall zone is disabled, instead of appearing to succeed. A disabled
  zone is skipped entirely by the firewall, so the setting was being written and
  read back correctly while having no effect at all.
- Fixed: the Remote LAN Access status column now uses per-terminal padding
  matched to how each glyph actually renders. On terminals that draw emoji at a
  different width than they report, the Active/Inactive/Remote-only markers no
  longer push the table out of alignment.
- New: on startup the toolkit now checks the real terminal size and says plainly
  if the window is too small, including how many columns or rows are missing. It
  already asks the terminal to resize itself, but some terminals ignore that
  request silently, so this tells you rather than leaving you with a wrapped
  table. Offers a recheck, because several terminals show no size indicator.
- Changed: the OpenVPN MTU recommendation is now derived from the tunnel's actual
  cipher and transport instead of a fixed conservative allowance. Measured against
  a live tunnel, UDP with AES-256-GCM costs 52 bytes, not the 69 previously
  assumed — so a 1500-byte link now recommends 1448 rather than 1431, recovering
  17 bytes of payload on every packet. Where the cipher cannot be determined the
  old conservative figure is still used.
- Added diffutils to the optional package manager.
- New: Remote LAN Access under VPN Tools — a single screen that explains, in
  plain terms, exactly which traffic can cross your VPN tunnel and which cannot,
  and lets you change it. It enumerates every source-and-destination combination
  in both directions rather than showing one summary line, so "it doesn't work"
  becomes a specific row with a specific reason.
- Each row is marked Active, Inactive, or Remote only. "Remote only" means the
  setting lives on the other router and cannot be changed from here — previously
  the most common source of confusion when remote LAN access silently failed.
- Detects the remote LAN subnet automatically where that is possible: from the
  tunnel's own configuration, by querying the remote router over SSH when key
  trust exists, or by probing well-known gateway addresses. Values that were
  guessed rather than read are marked with an asterisk, because a probed subnet
  assumes a /24 that may be wrong.
- Routes and per-peer authorisation are written to GL's own configuration keys,
  so changes appear in the GL web UI under Route Rules and survive a reboot.
- Firewall changes that could cut your own connection now apply under
  commit-confirm: the change is made, and reverts automatically after 30 seconds
  unless you confirm you are still connected. The revert runs detached, so it
  still happens if the session dies mid-change.
- Refuses outright to route between two identical subnets, and never proposes a
  probed subnet that matches your own LAN.
- Reachability testing is honest about what it cannot know: inbound can only be
  proven by the remote router, so it is reported as untestable rather than
  guessed from local configuration.
- The tunnel line reports what it can actually measure: WireGuard shows the real
  time since the last handshake, and flags a peer that has never connected at all
  — which is the first thing to check when nothing works. OpenVPN exposes no
  handshake time, so none is claimed for it.
- Router-to-router SSH key trust can be set up from the screen, letting the
  toolkit query and test the far side without a password each time. Keys the
  toolkit installs are tagged, so revoking removes only its own key and leaves
  any you added by hand untouched.

## 2026-07-21
- New: VPN Tools menu with an MTU Optimizer — detects your active WireGuard and
  OpenVPN tunnels and recommends the right MTU (underlay link MTU minus the
  protocol overhead), so VPN traffic stops fragmenting. Apply with one keypress,
  set manually, clear the override, or run an optional active probe.
- The MTU is written to the router's own VPN configuration, so it shows up in
  the GL web UI under that tunnel's Options and survives a reboot.
- On routers with more than one tunnel, Optimize and Reset can act on every
  tunnel at once ([A] All), each with its own correct value.
- Reset MTU removes the override outright. On older firmware the web UI can set
  an MTU but not clear it again, so this is the only way to get a tunnel back to
  the router's own default.
- Fixed: View UCI → VPN Configuration now recognizes GL's WireGuard/OpenVPN
  servers and clients instead of only stock-OpenWrt configs, so it no longer
  reads "No active VPN configurations found" on server-only routers.

## 2026-07-12
- Hardware Info reports Wi-Fi MIMO from the driver's configured antenna
  chainmask (correct 2x2 / 3x3 / 4x4 per band) instead of inferring it from the
  channel width, which mislabeled radios that run more than two spatial streams.

## 2026-07-10
- Change Log & Updates are now one screen: browse the full history in the house
  pager and update in place with `[U]` — the separate "Check for Updates" item
  is gone.
- Toolkit Management STATUS now shows your running version and whether an update
  is available.
- The changelog viewer marks where your installed version sits, so everything
  above the line is what's new to you.

## 2026-07-09
- Benchmark leaderboards expanded — added Flint 2, Beryl AX, Brume 3, Flint 3,
  and Beryl (original) as reference devices.
- VPN & Crypto benchmark now paginates by test (WireGuard / OpenVPN / RSA on
  their own pages), so it stays readable as the device list grows.
- Memory benchmark runs much faster on low-RAM devices (smaller test size).
- Terminal auto-sizing and a dark theme on launch, restored when you exit.
- More reliable terminal detection: it requires a real `stty` and, when it
  can't probe, falls back to clean Compatible mode instead of a mixed profile.
- Display Settings now shows your saved default, and your preference survives
  script updates.
- New: see what's changed before updating, plus a "Display Change Log" option
  under Toolkit Management.

## 2026-07-04
- Cross-device benchmark leaderboards (VPN & Crypto, Disk, Memory), ranked
  against saved reference routers instead of a single baseline.
- Renders correctly in PuTTY and Windows Terminal, not just macOS/iTerm
  (adaptive symbol set that avoids garbled boxes and misaligned columns).
- Robust CPU frequency detection (lscpu / cpufreq sysfs / device-tree OPP).
- Install as a system command (Toolkit Management) with sysupgrade persistence.
- UI/UX standardization pass across menus: input prompts, alignment, dividers,
  and spacing.
- Restore only offers components that were actually backed up.

## 2026-04-19
- Clearer wording in the zram swap tuning help.

## 2026-04-16
- Web terminal (ttyd) now supports HTTPS.

## 2026-04-10
- New: browser-based web terminal (ttyd) launched straight from the router.

## 2026-03-21
- New: guest-network controls — set per-guest speed limits and optionally allow
  the guest network to reach the router.

## 2026-03-15
- Refined fan-speed calculation.

## 2026-03-13
- Fan control now shows a live, real-time readout.
- New: iperf network performance testing.

## 2026-03-12
- Faster Hardware Information screen with UI polish.
- Better hardware detection on older routers.
- Fixed a rounding error in manual fan control.

## 2026-03-11
- New: System Tweaks menu — fan control, package manager, and SSH-key install.
- Fixed the Apache benchmark package dependency (apache-utils → apache).

## 2026-03-05
- New: install a LibreSpeed test server.

## 2026-03-02
- New: Ookla Speedtest Server benchmark.
- Stress test display supports a wider range of devices and temperatures.

## 2026-03-01
- More reliable CPU info (lscpu) and disk-space reporting when AdGuardHome was
  never installed.
- Unified benchmark UI.

## 2026-02-28
- New: real-time monitoring of CPU fan, temperature, and uptime.
- Falls back to stress-ng where stress isn't available on OpenWrt.

## 2026-02-22
- Menu option updates.

## 2026-02-21
- Fixed memory and storage calculation on the Beryl (original).

## 2026-02-20
- New: OpenSpeedTest server installer — the toolkit is now all-in-one.
- AdGuardHome handles client requests.
- Assorted UI fixes.

## 2026-02-19
- Fixed disk-size detection.
- Benchmark UI formatting fixes, including the Memory I/O test.

## 2026-02-15
- Major reorganization of the toolkit.
- New: SOS AdGuardHome factory restore.
- Expanded benchmark suite and added LAN info.
- More precise DNS benchmark.

## 2026-02-11
- New: manage AdGuardHome direct access.
- New: clean up old backups.
- Unified GUI elements.

## 2026-02-10
- Wireless detection now reports interface, band, HT mode, MIMO, and channel for
  each radio.
- AdGuardHome maintenance grouped under an "AdGuardHome Maintenance Hub."

## 2026-02-08
- First public release.
- AdGuardHome Lists Manager, wireless interface detection, and refined menus,
  help text, and install/removal flows.

## 2026-02-07
- Initial toolkit script.
