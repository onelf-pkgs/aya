#!/bin/sh
# Builds Aya for this machine's architecture into dist/:
#
#   aya-<arch>.onelf
#
# Nothing is compiled: upstream's AppImage already carries the Electron
# runtime, the app and its bundled adb; the recipe assembles them into
# one tree. Chromium's own dependencies come from the build container
# into the bundle; the GTK toolkit comes from the shared gtk3 set at
# launch, and GL from the host or the pinned GL build. The bundle
# updates itself from the latest release,
# accepting only updates signed with update.pub when the repository has
# one, and unsigned ones until then.
#
# Usage: build.sh
#
# Runs as root in a Void Linux (glibc) container with this directory as
# the working directory and onelf on PATH.
set -eu
cd "$(dirname "$0")"

arch=$(uname -m)
[ "$arch" = x86_64 ] || {
    echo "upstream publishes this release only for x86_64, not $arch" >&2
    exit 1
}

# toml <table> <key>: the string value of <key> in [<table>] of
# package.toml.
toml() {
    awk -v table="[$1]" -v key="$2" '
        /^\[/ { in_table = ($0 == table); next }
        in_table && $1 == key && $2 == "=" { gsub(/"/, "", $3); print $3; exit }
    ' package.toml
}

version=$(toml sources.aya version)
release=$(sed -n 's/^release = //p' package.toml)

# The desktop stack the pack pins instead of carrying: the gtk3 set
# from the gtk repository and the GL build from the mesa repository,
# both fetched and verified at launch.
gtk3_set_version=$(toml sets.gtk3 version)
gtk3_set_url=$(toml sets.gtk3 url | sed "s/{version}/$gtk3_set_version/; s/{arch}/$arch/")
gtk3_set_blake3=$(toml sets.gtk3.blake3 "$arch")
gl_version=$(toml gl-build version)
gl_url=$(toml gl-build url | sed "s/{version}/$gl_version/; s/{arch}/$arch/")
gl_blake3=$(toml gl-build.blake3 "$arch")
if [ -z "$gtk3_set_blake3" ]; then
    echo "the gtk3 set for $arch is not pinned yet; fill [sets.gtk3.blake3] from gtk v$gtk3_set_version" >&2
    exit 1
fi
if [ -z "$gl_blake3" ]; then
    echo "the GL build for $arch is not pinned yet; fill [gl-build.blake3] from mesa v$gl_version" >&2
    exit 1
fi

# The runtime installs only a strictly newer revision, so a client is
# never rolled back: 1.14.2 release 1 is 10014000001. awk reads Ventoy's
# zero-padded parts, such as the 05 of 1.1.05, as decimal.
revision=$(echo "$version.$release" | awk -F. '
    NF != 4 { exit 1 }
    { for (i = 2; i <= 4; i++) if ($i >= 1000) exit 1 }
    { printf "%.0f", $1 * 1e9 + $2 * 1e6 + $3 * 1e3 + $4 }
') || {
    echo "version $version release $release does not fit an update revision" >&2
    exit 1
}
if [ -f update.pub ]; then
    trust="key = \"$PWD/update.pub\""
else
    trust="unsigned = true"
fi

xbps-install -Syu xbps > /dev/null
xbps-install -Syu > /dev/null
xbps-install -y curl file findutils patchelf > /dev/null
# Chromium's own dependencies; the container supplies them so the
# bundle does not have to trust the host. The GTK stack is not
# installed: the shared gtk3 set answers it at launch, and GL from the
# pinned GL build. Chromium's own SwiftShader stays as the renderer
# when neither answers.
xbps-install -y nss cups alsa-lib dbus-libs wayland libdrm libxkbcommon \
    libX11 libXcomposite libXdamage libXext libXfixes libXrandr \
    libXcursor libXi libXtst libXScrnSaver > /dev/null

work=$PWD/build/work
file=build/src/AYA-$version-x86_64.AppImage
if [ ! -f "$file" ]; then
    mkdir -p build/src
    url=$(toml sources.aya url | sed "s/{version}/$version/")
    curl -fL --retry 3 --retry-all-errors -o "$file.part" "$url"
    mv "$file.part" "$file"
fi
echo "$(toml sources.aya sha256)  $file" | sha256sum -c - > /dev/null

rm -rf "$work"
mkdir -p "$work"
chmod +x "$file"
# --appimage-extract reads the squashfs payload without FUSE; the
# runtime needs only the container's glibc to do it.
cd "$work" && "$OLDPWD/$file" --appimage-extract > /dev/null
cd "$OLDPWD"

payload=$work/squashfs-root
tree=$work/aya
cp -a "$payload/." "$tree/"

# The AppImage's own launcher, menu file and icon: the launcher's job
# is taken by the aya-run script below, and the menu file and the icon
# move into .onelf/ and share/, and upstream's electron-updater config
# would fight the bundle updating itself.
rm "$tree/AppRun" "$tree/aya.desktop" "$tree/aya.png" \
    "$tree/resources/app-update.yml"

# The legacy tray and GConf libraries cannot resolve their own
# dependencies outside Ubuntu; Chromium loads them opportunistically and
# falls back without them.
rm -f "$tree"/usr/lib/libappindicator.so.* "$tree"/usr/lib/libindicator.so.* \
    "$tree"/usr/lib/libgconf-2.so.*

# The remaining libraries move into lib/, where the packed file's
# RUNPATH reaches them; the icons move into share/, where the runtime
# points XDG_DATA_DIRS.
mkdir -p "$tree/lib"
mv "$tree"/usr/lib/*.so* "$tree/lib/"
mv "$tree/usr/share" "$tree/share"
rmdir "$tree/usr/lib" "$tree/usr"

# Chromium parses fontconfig configs with the copy of fontconfig it
# bundles, which is older than Void's and prints a warning per rule it
# cannot read. The three rules are optional aliases for generic font
# families; the UI does not use them.
rm -f "$tree"/share/fontconfig/conf.avail/48-guessfamily.conf \
      "$tree"/share/fontconfig/conf.avail/49-sansserif.conf \
      "$tree"/share/fontconfig/conf.avail/49-spacing.conf \
      "$tree"/share/fontconfig/conf.d/48-guessfamily.conf \
      "$tree"/share/fontconfig/conf.d/49-sansserif.conf \
      "$tree"/share/fontconfig/conf.d/49-spacing.conf

# Upstream ships the Electron binary with RPATH $ORIGIN, enough for its
# own root-level libraries; the packed closure lives in lib, and onelf's
# rewriter fills only an absent RPATH. Extend it here, so the binary
# reaches both the libraries it ships beside itself and the ones the
# container supplies.
patchelf --set-rpath '$ORIGIN:$ORIGIN/lib' "$tree/aya"

# The menu entry and the icon, the way the recipe's integrate finds
# them.
mkdir -p "$tree/.onelf/desktop" "$tree/.onelf/icons"
cp desktop/aya.desktop "$tree/.onelf/desktop/aya.desktop"
cp "$tree/share/icons/hicolor/512x512/apps/aya.png" "$tree/.onelf/icons/default.png"

# The entrypoint is this launcher, not the Electron binary itself. The
# Chromium sandbox needs unprivileged user namespaces or a SUID-root
# helper, neither of which a pack can provide, so the app runs with it
# off, exactly what upstream's own desktop file does (Exec=AppRun
# --no-sandbox %U). Electron defaults to the X11 ozone platform, which
# dies on a Wayland-only session with no XWayland, so the launcher
# names Wayland when a Wayland socket is in the environment and lets
# X11 stand otherwise. The launcher runs from the tree root, where
# working-dir = command puts the cwd.
cat > "$tree/aya-run" <<'EOF'
#!/bin/sh
if [ -n "${WAYLAND_DISPLAY:-}${WAYLAND_SOCKET:-}" ]; then
    exec ./aya --no-sandbox --ozone-platform=wayland "$@"
fi
exec ./aya --no-sandbox "$@"
EOF
chmod 755 "$tree/aya-run"

for needed in \
    "$tree/aya" \
    "$tree/aya-run" \
    "$tree/resources/app.asar" \
    "$tree/resources/adb/adb" \
    "$tree/resources/scrcpy.jar" \
    "$tree/resources/aya.dex" \
    "$tree/icudtl.dat" \
    "$tree/resources.pak" \
    "$tree/v8_context_snapshot.bin" \
    "$tree/locales/en-US.pak" \
    "$tree/lib/libXss.so.1" \
    "$tree/lib/libXtst.so.6" \
    "$tree/lib/libnotify.so.4" \
    "$tree/share/icons/hicolor/512x512/apps/aya.png" \
    "$tree/.onelf/desktop/aya.desktop" \
    "$tree/.onelf/icons/default.png"
do
    [ -e "$needed" ] || {
        echo "the tree is missing $needed" >&2
        exit 1
    }
done

# The recipe is checked in beside this script; its placeholders expand
# from this environment when onelf loads it. The update section names
# this architecture's asset, so it is added here.
export AYA_VERSION=$version
export GTK3_SET_URL=$gtk3_set_url
export GTK3_SET_BLAKE3=$gtk3_set_blake3
export GL_URL=$gl_url
export GL_BLAKE3=$gl_blake3
cp onelf.toml "$tree/onelf.toml"
cat >> "$tree/onelf.toml" <<EOF

[update]
url = "https://github.com/onelf-pkgs/aya/releases/latest/download/aya-$arch.onelf"
revision = $revision
$trust
EOF

mkdir -p dist
onelf build "$tree" -o "dist/aya-$arch.onelf"

ls -l dist
