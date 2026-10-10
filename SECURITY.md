# Security policy

## Reporting a vulnerability

Please **don't** open a public issue for security problems. Report them privately through GitHub:
**[Report a vulnerability](https://github.com/Pacuka/fotoroll/security/advisories/new)**
(Security tab → "Report a vulnerability").

Please include what is affected, how to reproduce it, and the Fotoroll version. You'll get a reply as
soon as possible; fixes are released as a new version, and the advisory is published once users can
update.

Vulnerabilities in the Immich **server** should go to the
[Immich project](https://github.com/immich-app/immich/security).

## What Fotoroll stores

- Your server address and login (session token or API key) in the system keyring (libsecret / Secret
  Service). Only if no keyring is available, in `~/.config/fotoroll/credentials.json` with
  permissions `0600`.
- App and backup settings in `~/.config/fotoroll`, backup state in `~/.local/share/fotoroll`.

Fotoroll talks only to your Immich server and, for the map, to the tile servers of the selected map
style (OpenStreetMap by default). It has no telemetry.

## Supported versions

Only the latest release gets security fixes.
