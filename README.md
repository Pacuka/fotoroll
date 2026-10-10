<p align="center"><img src="assets/branding/fotoroll.png" width="128" alt=""></p>

# Fotoroll

A native Linux desktop client for your [Immich](https://immich.app) server, built with Flutter (GTK).
It aims to bring everything from the official web and mobile apps to the desktop, without a browser.

> **Unofficial.** Fotoroll is an independent project, not affiliated with or endorsed by the
> Immich team / FUTO. "Immich" is a trademark of its respective owner and is used here only to
> say which server this app talks to.

## Features

- **Login** with email + password or an API key (stored in the system keyring via libsecret)
- **Photos timeline** like the web: justified rows, day headers, year scrubber, memory lane ("1 year ago")
- **Viewer**: zoom, video playback (libmpv), keyboard navigation, editable info panel
  (description, date/time, location with map picker, rating, people, albums, tags); face editing:
  highlight, reassign or delete faces, tag a new face by drawing a box
- **360° / 180° photo spheres and 360° videos** in an interactive panorama viewer (drag to look around,
  scroll to zoom; partial panoramas use the photo's GPano data)
- **Live / motion photos**: badge and hover playback in the timeline, "Play Motion Photo" in the viewer
- **Slideshow** from the viewer or an album: shuffle / forward / backward, blurred-background look,
  progress bar, fade, info overlay, repeat, full screen
- **Hover video preview** in the timeline
- **Selection & bulk actions**: favorite, archive, trash / restore / delete, add to / remove from album,
  download as zip, move to locked folder
- **Explore**: people, places, recently added; **Map** with several tile styles
- **Albums**: create, rename, cover, order, share with users (roles), share links, comments toggle
- **Sharing**: shared albums, partners, shared links management
- **Library pages**: Favorites, Tags, Folders, Archive, Locked folder (PIN), Trash, Utilities
  (duplicates, large files), People management (rename, birth date, hide, merge)
- **Account settings** and **Administration** (users, libraries, jobs, all system settings, maintenance)
- **Folder backup**: watches selected folders while the app runs and uploads new photos and videos
  (SHA-1 de-duplication, excluded subfolders; local files are never changed)
- **Desktop integration**: drag & drop files or folders onto the window to upload, system tray
  (open / back up now / quit), keep running in the tray when closed, start at login hidden in the tray,
  single instance. The tray needs `libayatana-appindicator` (or the older `libappindicator-gtk3`); on
  GNOME also the AppIndicator extension.
- **Translations**: every language Immich itself ships

See [docs/PARITY.md](docs/PARITY.md) for the full feature checklist against the official clients.

### Keyboard shortcuts

| Where | Key | Action |
|---|---|---|
| Viewer | `←` `→` | Previous / next |
| Viewer | `Esc` | Back |
| Viewer | `I` | Info panel |
| Viewer | `D` | Download |
| Viewer | `F` / `A` / `Del` | Favorite / archive / trash |
| Viewer, slideshow | `F11` | Full screen |
| Slideshow | `Space` / `←` `→` / `Esc` | Pause / previous, next / exit |
| Timeline | `Ctrl+A` / `Esc` / `Del` | Select all / clear selection / trash selected |

## Requirements

- An Immich server, tested against **v3.1.0**
- Runtime libraries: `gtk3`, `mpv` (libmpv), `libsecret`; optional `libayatana-appindicator` for the tray
- To build: [Flutter](https://docs.flutter.dev/get-started/install/linux) (stable), `clang`, `cmake`,
  `ninja`, `pkg-config`

On Arch / CachyOS: `sudo pacman -S gtk3 mpv libsecret clang cmake ninja pkgconf`

## Download

**AppImage** (any x86-64 Linux with glibc 2.35+, e.g. Ubuntu 22.04, Debian 12, Fedora 36 or newer;
video playback is bundled, nothing else to install):

```bash
chmod +x Fotoroll-*-x86_64.AppImage
./Fotoroll-*-x86_64.AppImage
```

Releases attach the AppImage automatically (`.github/workflows/appimage.yml`).

## Build and install

```bash
flutter run -d linux        # development
./install.sh                # build + install to ~/.local (no root) + app menu entry
./install.sh --uninstall    # remove (settings and backup state are kept)
```

Build the AppImage yourself (in an Ubuntu 22.04 podman container, from any distro):

```bash
tool/build_appimage.sh      # → build/appimage-out/Fotoroll-<version>-x86_64.AppImage
```

Where things live:

| Path | Contents |
|---|---|
| `~/.local/lib/fotoroll` | the installed app (`fotoroll` command in `~/.local/bin`) |
| `~/.config/fotoroll` | app and backup settings |
| `~/.local/share/fotoroll` | backup state (which files were already uploaded) |


## Development

- All server calls are in `lib/api.dart`. After a server upgrade, check the Immich changelog for API
  changes and update only that file.
- UI strings come from Immich's own translation files (`tool/update_translations.sh`); strings that
  exist only in this app are in `assets/i18n_app` (`tool/app_strings.py`).
- Admin system settings are generated from the web source (`tool/gen_system_settings.py`).

### Tests

```bash
flutter analyze
flutter test                     # unit + widget tests (fake v3.1.0 responses)
tool/run_integration_tests.sh    # the real desktop app against an in-memory fake Immich server
```

The integration tests open every page, use the viewer, play videos, edit metadata, search with filters,
select and favorite photos, look around in 360° and 180° panoramas, and fail on any frame slower than
250 ms during hover previews. Panorama test images come from `tool/make_pano_fixtures.py`.

## Credits

- [Immich](https://immich.app) (AGPL-3.0): the server this app talks to; UI translations come from
  its translation files, and the admin settings are generated from its web client
- [Flutter](https://flutter.dev), [media_kit](https://github.com/media-kit/media-kit) / mpv / FFmpeg,
  [flutter_map](https://github.com/fleaflet/flutter_map) with OpenStreetMap tiles

## License

[AGPL-3.0](LICENSE), the same license as Immich.
