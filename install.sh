#!/usr/bin/env bash
# Builds Fotoroll and installs it for the current user (no root needed).
# Remove with: ./install.sh --uninstall
#
# The app goes to ~/.local/lib/fotoroll. ~/.config/fotoroll (settings) and
# ~/.local/share/fotoroll (backup state: which files were already uploaded) are
# never touched here.
set -euo pipefail
cd "$(dirname "$0")"

APP_ID="io.github.pacuka.Fotoroll"
DEST="$HOME/.local/lib/fotoroll"
DESKTOP="$HOME/.local/share/applications/$APP_ID.desktop"
ICON="$HOME/.local/share/icons/hicolor/512x512/apps/$APP_ID.png"
BIN="$HOME/.local/bin/fotoroll"

# Installs made while the app was still called "immich-linux". Only the app files
# go; the settings and backup state there are moved over by the app itself.
remove_legacy() {
  local old_share="$HOME/.local/share/immich-linux"
  if [[ -x "$old_share/immich_linux" ]]; then
    rm -rf "$old_share/immich_linux" "$old_share/lib" "$old_share/data"
  fi
  rm -rf "$HOME/.local/lib/immich-linux"
  rm -f "$HOME/.local/share/applications/immich-linux.desktop" "$HOME/.local/bin/immich-linux"
}

if [[ "${1:-}" == "--uninstall" ]]; then
  rm -rf "$DEST" "$DESKTOP" "$ICON" "$BIN"
  remove_legacy
  echo "Uninstalled. Settings (~/.config/fotoroll) and backup state (~/.local/share/fotoroll) were kept."
  exit 0
fi

flutter build linux --release
case "$(uname -m)" in
  aarch64|arm64) ARCH=arm64 ;;
  *) ARCH=x64 ;;
esac
BUNDLE="build/linux/$ARCH/release/bundle"
[[ -x "$BUNDLE/fotoroll" ]] || { echo "Build output not found in $BUNDLE" >&2; exit 1; }

# Copy next to the old install first, so a failed copy never leaves you without an app.
mkdir -p "$(dirname "$DEST")" "$(dirname "$DESKTOP")" "$(dirname "$BIN")" "$(dirname "$ICON")"
rm -rf "$DEST.new"
cp -r "$BUNDLE/." "$DEST.new/"
rm -rf "$DEST"
mv "$DEST.new" "$DEST"
remove_legacy
ln -sf "$DEST/fotoroll" "$BIN"
cp assets/branding/fotoroll.png "$ICON"

cat > "$DESKTOP" <<DESK
[Desktop Entry]
Type=Application
Name=Fotoroll
GenericName=Photo Library
Comment=Browse, back up and manage the photos on your Immich server
Exec=$DEST/fotoroll
Icon=$APP_ID
Terminal=false
Categories=Graphics;Photography;
Keywords=immich;photos;gallery;backup;
StartupWMClass=$APP_ID
DESK

update-desktop-database "$(dirname "$DESKTOP")" 2>/dev/null || true
gtk-update-icon-cache -q -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
echo "Installed to $DEST"
echo "Start it from the app menu (Fotoroll) or run: fotoroll"
