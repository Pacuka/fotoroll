# Feature parity with the official Immich clients (v3.3.3)

Source of truth: `immich-app/immich@v3.1.0`, plus the v3.3.3 delta below (web routes in `web/src/routes`, mobile pages in
`mobile/lib/**/pages`). ✅ done · 🟡 partial · ⬜ todo · ➖ not applicable on desktop

## New in Immich v3.2 – v3.3.3 (catch-up list)
Endpoint moves are done (`/config`, `/admin/config`, `POST /people/merge`, with v3.1 fallback) and the
translations come from v3.3.3. User-facing features still to do, in planned order:

| Feature | Web source | Status |
|---|---|---|
| Sharing settings: cluster group (invite users, pending requests, accept/decline, leave, reset facial recognition) | `user-settings/SharingSettings.svelte` | ✅ |
| Shared people: manage access per person and in bulk, "shared with me" indicator, filter people by shared by / with | `PersonEditAccessModal`, `PersonBulkShareModal`, `PeopleFilterModal`, `PersonIndicator` | ✅ (also "aka" names) |
| Person edit: name + birth date in one dialog, "only change for me" for shared people; Features → people update strategy | `PersonEditModal`, `FeatureSettings.svelte` | ✅ |
| Memories page (current / upcoming, favorite memories, filters) and birthday memories | `/memories`, `MemoryCard`, `MemoriesSettingsModal` | ✅ (sidebar entry, Explore section; no confetti) |
| Album editors can change title & description | `album.service.ts` | ✅ |
| API key rotate | `api-key.service.ts` | ⬜ |
| Tag renaming | `TagEditModal` | ⬜ |
| Map: show assets in the current viewport | `map/` | ⬜ |
| Slideshow: metadata overlay mode (full / description only) | `SlideshowSettingsModal` | ✅ (already there) |
| Revamped search dialog (same filters, new layout) | `search-bar/` | ⬜ (ours already has every filter) |

## Main navigation (web sidebar)
| Feature | Web route | Status |
|---|---|---|
| Photos timeline (justified rows, day headers, year scrubber) | `/photos` | ✅ |
| Explore: people, places, recently added | `/explore` | ✅ |
| Map with markers + area photo list, map style switcher (OSM, dark, HOT, topo, cycling, Sentinel-2 satellite, Esri HD satellite) | `/map` | ✅ |
| Sharing: shared albums, partners, shared links button | `/sharing` | 🟡 no create shared album yet |
| Favorites | `/favorites` | ✅ |
| Albums: list (search, filter, sort), create, rename, description, cover, display order, comments toggle, share with users (roles), share link, add/remove photos, download, delete, leave | `/albums` | ✅ (no activity panel yet) |
| Utilities: duplicates, large files | `/utilities/*` | 🟡 no geolocation tool, no workflows |
| Archive | `/archive` | ✅ |
| Locked folder (PIN) | `/locked` | ✅ |
| Trash: restore / empty | `/trash` | ✅ |
| Folders view (path tree + folder timeline) | `/folders` | ✅ |
| Tags (tree, tag timeline, delete) | `/tags` | ✅ |
| Memories ("x years ago" lane + viewer: autoplay, pause, prev/next, mark seen) | `/memory` | ✅ |
| Shared links management (list, edit, copy, delete) | `/shared-links` | ✅ |
| People: all, show & hide, rename, birth date, favorite, merge | `/people`, `/people/manage` | ✅ |
| Places (all, by country) | `/places` | ✅ |
| Recently added | `/recently-added` | ✅ |
| Partner timeline | `/partners/[id]` | ✅ |
| Search with filters (people, text modes incl. OCR & path, tags, place, camera, date, rating, type, display options) | `/search` | ✅ (no search history yet) |
| Workflows | `/workflows` | ⬜ |

## Asset viewer
| Feature | Status |
|---|---|
| Image zoom, video playback, prev/next, keyboard | ✅ |
| Info panel: date, file, camera, place, people (age), albums, tags, rating | ✅ |
| Favorite, archive, trash/restore, add to album, download, locked folder | ✅ |
| Edit description, date/time, location (map picker), rating, tags | ✅ |
| Faces: hover a face on the photo (box + name) or a person in the panel, edit faces (reassign, new person, delete), tag a face by drawing a box | ✅ |
| Editor (crop, rotate, filters) | ⬜ |
| Slideshow (shuffle / forward / backward, contain / cover / blurred, progress bar, fade, video autoplay, repeat, info overlay, full screen) | ✅ |
| Activity / comments / likes (shared albums) | ⬜ |
| Stacks | ⬜ |
| Live / motion photos (badge, hover playback, "Play Motion Photo" in the viewer) | ✅ |
| 360° / 180° panorama photos (GPano crop, drag / zoom, 360 badge on tiles) and 360° videos (mpv v360) | ✅ |
| Share (shared link) | ⬜ |

## Selection & bulk actions
| Feature | Status |
|---|---|
| Multi-select (click, shift range, whole day, Ctrl+A) | ✅ |
| Favorite, archive, trash, delete permanently, restore, add to album, remove from album, download zip, locked folder | ✅ |
| Change date / location, stack, tag, share link | ⬜ |

## Account settings (web `/user-settings`)
| Section | Status |
|---|---|
| App settings (language from Immich i18n, theme) | ✅ |
| Account (name, email) | ✅ (no profile picture upload yet) |
| Usage statistics | ✅ |
| API keys | ✅ |
| Authorized devices | ✅ |
| Download / Features / Notifications preferences | ✅ |
| Password | ✅ |
| Sharing (people cluster group + partners) | ✅ |
| PIN code | ✅ |
| Purchase | 🟡 status only |
| OAuth link/unlink | ⬜ |

## Administration (web `/admin`)
| Section | Status |
|---|---|
| Users: list, create, detail page, edit (email, name, quota, storage label, admin), reset password, reset PIN, delete, restore | ✅ (no upload heatmap yet) |
| External libraries | ✅ |
| Job queues: start/pause/resume | ✅ (no queue detail page) |
| System settings (all 19 sections, generated from web source) | ✅ |
| Maintenance: mode, database backups | 🟡 no restore/upload, no integrity report |
| Server stats | ✅ |

## Auth
| Feature | Status |
|---|---|
| Login (password, API key) | ✅ |
| OAuth login | ⬜ |
| Forced password change, onboarding, admin registration | ⬜ |

## Mobile-only features worth having on desktop
| Feature | Status |
|---|---|
| Folder backup (watched folders, dedupe by checksum) | ✅ |
| Upload detail / per-file status | 🟡 |
| Custom proxy headers (`headers_settings`) | ⬜ |
| App log viewer | ⬜ |
| Offline cache | ⬜ |

## Desktop extras (beyond the official clients)
| Feature | Status |
|---|---|
| System tray (open / back up now / quit), close to tray, autostart hidden in the tray, single instance | ✅ |
| Drag & drop files / folders to upload | ✅ (paste not yet) |
| Hover video preview | ✅ |
| Upload only on local network | ⬜ |
| Packaging: AppImage (Ubuntu 22.04 base, libmpv bundled, CI on tags) | ✅ |
| Packaging: Flatpak (Flathub), AUR, .deb, .rpm, Snap | ⬜ |

## How this is verified
- `flutter test` — unit + widget tests, incl. smoke tests that build every settings/admin screen.
- `tool/run_integration_tests.sh` — runs the real desktop app against an in-memory fake Immich server:
  visits every page (sidebar follows the user's Features → Sidebar prefs), opens a memory,
  browses folders, renames a person, edits in the viewer, plays a video, selects + favorites, hovers video previews
  and fails on any slow frame (>250 ms).
