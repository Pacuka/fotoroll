# AUR package (`fotoroll-bin`)

Repackages the release AppImage for Arch: it is extracted to `/opt/fotoroll`,
`/usr/bin/fotoroll` (`fotoroll.sh`) starts it, and the menu entry + icon go to
`/usr/share`. No FUSE needed. This folder is the source of truth; the AUR git
repo (`ssh://aur@aur.archlinux.org/fotoroll-bin.git`) gets a copy.

New release:

```sh
# in a scratch copy of this folder
sed -i "s/^pkgver=.*/pkgver=X.Y.Z/; s/^pkgrel=.*/pkgrel=1/" PKGBUILD
updpkgsums                         # pacman-contrib; or paste the output of makepkg -g
makepkg -f && makepkg --printsrcinfo > .SRCINFO
# copy PKGBUILD, fotoroll.sh and .SRCINFO into the AUR repo, commit, push
```

The AppImage's sha256 must match the digest GitHub shows for the release asset.
