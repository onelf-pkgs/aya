#!/bin/sh
# Tests the Aya package build.sh wrote. Runs in the same container,
# right after it.
#
# The container has no display, so the window never opens: the launch
# check walks the app as far as Electron goes without one. Aya's own
# "main: start" log line proves Electron booted and the packed app code
# ran; Chromium's ozone error proves every library resolved and the GTK
# stack loaded. What must never appear is a missing library, a missing
# file of the payload, or a broken asar.
#
# Usage: test.sh
set -eu
cd "$(dirname "$0")"

arch=$(uname -m)

packed=dist/aya-$arch.onelf
onelf verify "$packed"

# The payload is upstream's Electron runtime, the app, adb and scrcpy;
# Chromium's own libraries sit in lib and the toolkit comes from the
# gtk3 set at launch; the launcher, the updater config and the
# libraries that cannot resolve their own dependencies must be gone.
list=$(onelf list "$packed")
for path in aya resources/app.asar resources/adb/adb resources/scrcpy.jar \
    resources/aya.dex icudtl.dat resources.pak locales/en-US.pak \
    lib/libnss3.so lib/libcups.so.2 lib/libasound.so.2 \
    lib/libX11.so.6 lib/libwayland-client.so.0 \
    lib/libXss.so.1 lib/libXtst.so.6 lib/libnotify.so.4 \
    share/icons/hicolor/512x512/apps/aya.png \
    .onelf/desktop/aya.desktop .onelf/icons/default.png
do
    case $list in
    *"$path"*) : ;;
    *)
        echo "the package is missing $path" >&2
        exit 1
        ;;
    esac
done
# Everything under usr/ must be the icon the packer canonicalizes for
# the desktop integration; a leftover upstream tree would show up here too.
for path in $(printf '%s\n' "$list" | awk '{print $NF}' | grep -E '^usr'); do
    case $path in
    usr/share/icons/hicolor/*/apps/aya.png) : ;;
    *)
        echo "the package carries $path" >&2
        exit 1
        ;;
    esac
done
for path in AppRun app-update.yml libappindicator libgconf \
    onelf.toml
do
    case $list in
    *"$path"*)
        echo "the package carries $path" >&2
        exit 1
        ;;
    esac
done

# The launch must boot Electron and the app, then stop at the display:
# no window can open in a container without one.
log=$(mktemp)
if dist/aya-$arch.onelf --no-sandbox > "$log" 2>&1
then
    cat "$log" >&2
    echo "the app kept running without a display" >&2
    exit 1
fi
if grep -q "loading shared libraries" "$log"; then
    cat "$log" >&2
    echo "a library did not resolve at launch" >&2
    exit 1
fi
if grep -q "Cannot find module" "$log"; then
    cat "$log" >&2
    echo "the packed app code did not load" >&2
    exit 1
fi
grep -q "main: start" "$log" || {
    cat "$log" >&2
    echo "Electron did not boot the app" >&2
    exit 1
}
grep -qiE "Missing X server|cannot open display" "$log" || {
    cat "$log" >&2
    echo "the run stopped before the display stage" >&2
    exit 1
}
rm -f "$log"

echo "aya-$arch: verify, contents and launch ok"
