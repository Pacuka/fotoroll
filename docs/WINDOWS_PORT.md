# Windows port: plan and handoff

Fotoroll was built and tested on Linux only. This file is the starting point for
the Windows port (written so a new session on a Windows machine can pick it up).

## Status

- Not started. The Dart / Flutter code (UI, API, timeline, search, viewer,
  settings, admin, backup) is platform-neutral and should mostly work as is.
- Everything below is Linux-specific and needs a Windows path.

## Set up the Windows machine

1. Git for Windows
2. Visual Studio 2022 (Build Tools are enough) with **Desktop development with C++**
3. Flutter **3.47.5** stable (same as Linux), then `flutter doctor`
4. `git clone https://github.com/Pacuka/fotoroll` and `flutter create --platforms=windows .`
   (generates `windows/`; keep our `lib/`, `pubspec.yaml`, `assets/`)
5. Commit with the noreply address: `git config user.email "69674426+Pacuka@users.noreply.github.com"`

## Linux-specific parts and what Windows needs

| Area | Linux (where) | Windows plan |
|---|---|---|
| Native window channel `fotoroll/window`: full screen, tray, close to tray, drag & drop, single instance | `linux/runner/my_application.cc` (GTK, AppIndicator via dlopen) | Same channel in the Windows runner (`windows/runner/`), or plugins: `window_manager` (full screen, close-to-tray), `tray_manager` (tray), `desktop_drop` (drag & drop), a named mutex for single instance. Keep `lib/window.dart` as the one Dart API. |
| Config / data dirs | `lib/app_dirs.dart` (XDG: `~/.config/fotoroll`, `~/.local/share/fotoroll`) | `%APPDATA%\Fotoroll` and `%LOCALAPPDATA%\Fotoroll` (or `path_provider`) |
| Credentials | `lib/session.dart` (libsecret; fallback file + `chmod 600`) | `flutter_secure_storage` uses Windows Credential Manager; the fallback must not call `chmod` |
| Downloads folder | `lib/widgets/asset_actions.dart` (`xdg-user-dir DOWNLOAD`) | Known folder Downloads (`%USERPROFILE%\Downloads` or `path_provider.getDownloadsDirectory`) |
| "Open folder" | `xdg-open` in `asset_actions.dart`, `viewer.dart`, `albums.dart` | `explorer.exe <dir>` (one helper, e.g. `openFolder()` in `window.dart`) |
| Backup folder picker defaults | `lib/screens/backup_screen.dart` (`HOME`) | `USERPROFILE` |
| Autostart | `lib/window.dart` (`~/.config/autostart/*.desktop`, `--hidden`) | `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` value with `"<exe>" --hidden` |
| AppImage menu entry | `lib/desktop_integration.dart` | Not needed (the installer creates Start menu shortcuts) |
| Video | `media_kit_libs_linux` (system libmpv) | add `media_kit_libs_windows_video` (bundles libmpv); 360° video uses mpv's `v360` filter, works the same |
| Panorama shader | `shaders/panorama.frag` | Same (Flutter fragment shaders work on Windows) |
| Packaging | `tool/build_appimage.sh`, `.github/workflows/appimage.yml` | Inno Setup installer (or MSIX) + a `windows-latest` GitHub Actions job on `v*` tags |

Search the code for these to find every spot:
`Process.run`, `xdg-`, `Platform.environment['HOME'`, `XDG_`, `/proc/`, `APPIMAGE`, `chmod`.

## How to verify (same standard as on Linux)

- `flutter analyze` and `flutter test` must pass.
- Integration tests: `flutter test integration_test/<name>_test.dart -d windows`, one file at
  a time (see `tool/run_integration_tests.sh`; on Windows a PowerShell loop does the same).
  They run the real app against `integration_test/fake_server.dart` and must not touch the
  user's real settings (they use temp dirs; keep it that way).
- Check the UI by eye on Windows: title bar buttons, tray icon, drag & drop, video, panorama.

## Suggested order

1. `flutter create --platforms=windows .`, make it build and log in.
2. Paths + open folder + downloads (small, unblocks everything).
3. Window channel features (full screen, tray, close to tray, drag & drop, single instance).
4. Autostart via registry.
5. Installer + CI job, release as a new version next to the AppImage.
