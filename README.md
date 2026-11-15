# aya

[AYA](https://aya.liriliri.io) packed for
[onelf](https://github.com/QaidVoid/onelf) packages. The application
is upstream's and its [README](https://github.com/liriliri/aya)
describes it; this repository only repacks it into one file that runs
on hosts with no desktop stack installed, without FUSE.

| | |
|---|---|
| Description | Android ADB desktop app |
| Upstream | <https://github.com/liriliri/aya> |
| License | AGPL-3.0 |

## The repack

- Carries Chromium's own libraries from the build container (NSS,
  CUPS, ALSA and the X11 and Wayland client libraries), which no host
  ships complete for Electron. Without GPU drivers Chromium renders
  through the carried SwiftShader.
- Pins the GTK toolkit to the shared gtk3 set instead of carrying it:
  the runtime fetches the set at launch, verifies it against a BLAKE3
  pin and shares one copy across every package that pins it.
- Answers GL the same way: hosts with a working stack use their own,
  hosts without one fetch the pinned GL build at launch. Chromium's
  GBM probe is loud against a half-present host stack, so libgbm is
  never carried, only answered from the host or the pinned build.
- Carries `libX11-xcb.so.1` explicitly, which Chromium dlopens by name
  and whose absence kills the app with a hardening trap on X11.
- Drops the electron-updater config and the Ubuntu-only tray libraries
  (libappindicator, libindicator, libgconf); the bundle updates itself
  from this repository's releases, unsigned until the control workflow
  commits a signing key.
- Launches through a small script instead of the Electron binary: it
  turns the Chromium sandbox off, which upstream's own desktop file
  does as well, and names Wayland when the session offers it, so a
  bare invocation works on X11 and Wayland alike.
- Installs a desktop entry and icon through onelf's integration.
- x86_64 only, like upstream's releases.

## Releases

Tagged `v<version>-<release>`; each release carries
`aya-<arch>.onelf`. `test.sh` runs in the build container right after
`build.sh`: it verifies the file, checks the payload and launches Aya
headless, which must reach Aya's own startup log (the launch fetches
the pinned set and GL build, as it would on a user's host). Beyond
it, the file rendered its full UI under Wayland on the build host
with no GL noise and no fontconfig warnings; ADB tracks devices.
