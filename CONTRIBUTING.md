# Contributing to Fotoroll

Thanks for helping! Bug reports, ideas and pull requests are all welcome.

## Reporting bugs and ideas

Use the [issue templates](https://github.com/Pacuka/fotoroll/issues/new/choose). For bugs, please
include your Immich server version, your distribution / desktop, and whether you use the AppImage or
your own build. Problems with the Immich **server** itself belong to the
[Immich project](https://github.com/immich-app/immich/issues).

Security issues: please don't open a public issue, see [SECURITY.md](SECURITY.md).

## Development setup

- [Flutter](https://docs.flutter.dev/get-started/install/linux) **3.47.5** (stable)
- Build tools: `clang cmake ninja pkg-config`, and `gtk3`, `mpv` (libmpv), `libsecret` development files
  - Arch: `sudo pacman -S clang cmake ninja pkgconf gtk3 mpv libsecret`
  - Debian / Ubuntu: `sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libmpv-dev libsecret-1-dev`
- `flutter run -d linux`

Where things are:

- `lib/api.dart`: every call to the Immich server (the only file to touch for API changes)
- `lib/screens/`, `lib/widgets/`: UI; `linux/runner/my_application.cc`: tray, drag & drop, full screen
- `docs/PARITY.md`: what's done / missing compared with the official Immich clients
- UI strings come from Immich's own translations (`tool/update_translations.sh`). Strings that only
  exist in this app live in `assets/i18n_app` (`tool/app_strings.py`). Please improve translations of
  Immich strings upstream on [Immich's Weblate](https://hosted.weblate.org/projects/immich/), not here.

## Before you open a pull request

Everything below runs in CI on every pull request; running it locally first saves a round trip.

```bash
flutter analyze                 # must report no issues
flutter test                    # unit + widget tests
tool/run_integration_tests.sh   # the real app against an in-memory fake Immich server
```

- New features and bug fixes come with a test. User-visible features get an integration test in
  `integration_test/` (see the existing ones: they drive the real app against `fake_server.dart`).
  Integration tests must never touch the user's real settings or data (use the temp-dir overrides).
- Match the style of the surrounding code; keep comments for the *why*.
- One topic per pull request, with a short description of what changed and how you tested it.

## Sign your commits (DCO)

Every commit must carry a `Signed-off-by` line, certifying the
[Developer Certificate of Origin 1.1](https://developercertificate.org/): that you wrote the change
(or otherwise have the right to submit it) and that it may be distributed under this project's
license. Add it with:

```bash
git commit -s
```

which appends `Signed-off-by: Your Name <your@email>` using your git identity. A CI check fails if a
commit in the pull request is not signed off; `git rebase --signoff main` fixes existing commits.

## License

Fotoroll is licensed under the [GNU AGPL-3.0](LICENSE). By contributing you agree that your
contribution is licensed under the same terms (no separate contributor agreement).

## Name and logo

"Fotoroll" and its logo identify this project; forks that are distributed should use their own name
and logo. Fotoroll is not affiliated with the Immich project or FUTO: please don't add the Immich
logo or present the app as an official Immich client. Mentioning that it works with Immich is fine.

## Code of conduct

This project follows the [Code of Conduct](CODE_OF_CONDUCT.md).
