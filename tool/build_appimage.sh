#!/usr/bin/env bash
# Builds the AppImage in an Ubuntu 22.04 podman container (works on any distro).
# Output: build/appimage/Fotoroll-<version>-x86_64.AppImage
set -euo pipefail
cd "$(dirname "$0")/.."
podman build -t fotoroll-appimage -f tool/appimage/Containerfile tool/appimage
# A separate build dir inside the container keeps the host's build/ (glibc 2.4x)
# from mixing with the container's; only the AppImage is copied out.
podman run --rm -v "$PWD":/src:ro -v "$PWD/build/appimage-out":/out:Z fotoroll-appimage bash -c '
  set -e
  cp -r /src /work && cd /work && rm -rf build .dart_tool linux/flutter/ephemeral
  tool/appimage/build.sh
  cp build/appimage/*.AppImage /out/'
ls -la build/appimage-out/
