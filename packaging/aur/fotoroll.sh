#!/bin/sh
# Starts the extracted AppImage. AppRun points the app at its bundled libraries
# (libmpv.so.1 and its ffmpeg, which Arch doesn't ship); FOTOROLL_LAUNCHER makes
# autostart call this script instead of the bare binary.
export FOTOROLL_LAUNCHER=/usr/bin/fotoroll
exec /opt/fotoroll/AppRun "$@"
