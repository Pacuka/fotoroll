#!/usr/bin/env bash
# Builds Fotoroll-<version>-x86_64.AppImage. Runs inside Ubuntu 22.04 (the
# Containerfile here, or a GitHub ubuntu-22.04 runner); use tool/build_appimage.sh
# to run it in podman from any distro.
set -euo pipefail
cd "$(dirname "$0")/../.."

VERSION="$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)"
OUT="build/appimage"
APPDIR="$OUT/AppDir"

flutter pub get
flutter build linux --release

rm -rf "$OUT"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/applications" "$APPDIR/usr/share/icons/hicolor/512x512/apps"
cp -r build/linux/x64/release/bundle/. "$APPDIR/usr/bin/"
cp tool/appimage/io.github.pacuka.Fotoroll.desktop "$APPDIR/usr/share/applications/"
cp assets/branding/fotoroll.png "$APPDIR/usr/share/icons/hicolor/512x512/apps/io.github.pacuka.Fotoroll.png"
desktop-file-validate "$APPDIR/usr/share/applications/io.github.pacuka.Fotoroll.desktop"

# Bundle libmpv (loaded by media_kit at run time, so not a link dependency) and
# everything the app links against, except the base system libraries.
LIBMPV="$(ldconfig -p | sed -n 's/.*\(libmpv\.so\.[0-9]*\) .*=> \(.*\)/\2/p' | head -n 1)"
linuxdeploy --appdir "$APPDIR" \
  --executable "$APPDIR/usr/bin/fotoroll" \
  --library "$LIBMPV" \
  --desktop-file "$APPDIR/usr/share/applications/io.github.pacuka.Fotoroll.desktop" \
  --icon-file "$APPDIR/usr/share/icons/hicolor/512x512/apps/io.github.pacuka.Fotoroll.png"
for lib in "$APPDIR"/usr/bin/lib/*.so; do
  # libapp.so is Dart AOT code: never patch it, it has no deps of interest anyway.
  [ "$(basename "$lib")" = libapp.so ] && continue
  linuxdeploy --appdir "$APPDIR" --library "$lib" >/dev/null
done
# linuxdeploy rewrites RPATHs (and copies the Flutter libs to usr/lib). Put the
# untouched Flutter bundle back - it finds its own lib/ via $ORIGIN - and drop
# the duplicates; usr/lib keeps only the third-party dependencies.
cp -r build/linux/x64/release/bundle/. "$APPDIR/usr/bin/"
for lib in "$APPDIR"/usr/bin/lib/*.so; do rm -f "$APPDIR/usr/lib/$(basename "$lib")"; done
# libmpv links libjack, which the AppImage excludelist leaves to the host - but
# not every desktop has it, and then libmpv (all video) fails to load. Only the
# loading needs it (audio goes through PulseAudio / PipeWire), so bundle it.
for lib in $(ldd "$LIBMPV" | awk '/libjack\.so/ {print $3}'); do
  cp -L "$lib" "$APPDIR/usr/lib/"
done

# linuxdeploy made AppRun a symlink to the binary: replace the link, not its target.
rm -f "$APPDIR/AppRun"
cp tool/appimage/AppRun "$APPDIR/AppRun"

ARCH=x86_64 appimagetool --no-appstream "$APPDIR" "$OUT/Fotoroll-$VERSION-x86_64.AppImage"
echo "Built $OUT/Fotoroll-$VERSION-x86_64.AppImage"
