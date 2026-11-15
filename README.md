# aya

[AYA](https://aya.liriliri.io) packed for
[onelf](https://github.com/QaidVoid/onelf) packages. The application
is upstream's and its [README](https://github.com/liriliri/aya)
describes it; this repository only repacks it into one file that runs
on hosts with no desktop stack installed, without FUSE.

| | |
|---|---|
| Description | Android ADB desktop app |
| Version | 1.14.2 |
| Upstream | <https://github.com/liriliri/aya> |
| License | AGPL-3.0 |

## The repack

- Carries the whole Electron runtime stack upstream leaves to the host
  (GTK 3, NSS, CUPS, ALSA, X11, Wayland, Mesa); without GPU drivers
  Chromium renders through the carried SwiftShader.
- Carries `libX11-xcb.so.1` explicitly, which Chromium dlopens by name
  and whose absence kills the app with a hardening trap on X11.
- Drops the electron-updater config and the Ubuntu-only tray libraries
  (libappindicator, libindicator, libgconf); the bundle updates itself
  from this repository's releases, unsigned until the control workflow
  commits a signing key.
- Installs a desktop entry and icon through onelf's integration.
- x86_64 only, like upstream's releases.

## Releases

Tagged `v<version>-<release>`; each release carries
`aya-<arch>.onelf`. `test.sh` runs in the build container: it verifies
the file, checks the payload and launches Aya headless, which must
reach Aya's own startup log. Beyond it, the file rendered its full UI
under Xvfb on Alpine (musl, no GPU) and launched under Wayland on the
build host; ADB tracks devices in both.
