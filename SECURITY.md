# Security

## Reporting a vulnerability

Please report security problems privately through
[GitHub's private vulnerability reporting](https://github.com/chocholous/QuadStatus/security/advisories/new),
not in a public issue. You can expect a first answer within a week.

## What QuadStatus does on your Mac

So you can judge it without reading all the code:

- **No network requests of its own.** The only traffic it creates is an ICMP echo to your
  router, and only while its menu is open, to measure latency.
- **No data leaves the Mac,** and nothing is written anywhere except its own preferences and,
  when you turn on Open at Login, one LaunchAgent:
  `~/Library/LaunchAgents/io.github.chocholous.quadstatus.login.plist`.
- **Commands it runs:** `/usr/sbin/system_profiler` (battery health, AirPods battery) and
  `/bin/launchctl` (loading and unloading that LaunchAgent). Both with fixed arguments.
- **Files it reads outside its own:** the Focus state the system keeps in your Library, and
  NordVPN's preferences (the last country), both read-only.
- **Permissions:** none required. Location access is optional and only unlocks the Wi-Fi
  network's name, which macOS hides from apps without it.
- **NordVPN** is controlled only through its public `nordvpn://` URL scheme.

## Builds

Releases are built from a tagged commit with `./build.sh --dmg`. They are ad-hoc signed,
not yet signed with a Developer ID or notarized by Apple. Each release lists the SHA-256 of
its disk image. To avoid trusting the binary at all, build from source: `./build.sh --install`.
