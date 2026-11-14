# Updates

## On the tablet

Everything updates from **Discover** (the app store):

* **Discover → Updates → Update All** installs
  * Alpine Linux packages (Plasma, Firefox, LibreOffice, graphics drivers, security fixes),
  * Flatpak apps from Flathub,
  * **Fire HD 8 Linux system updates**: `douglas-base` (device support) and
    `douglas-kernel` (the kernel).
* Discover checks in the background and shows a notification when updates are available.
* No password is needed for the person using the tablet (members of the `wheel` group in
  the active session). To require a password, see *Requiring a password* below.

### Kernel updates

When `douglas-kernel` is updated, its install script (`douglas-flash-kernel`):

1. checks it is running on a Fire HD 8 and the new image is valid (header, checksum, size),
2. saves the running kernel to `/var/lib/douglas/boot_x.previous.img`,
3. writes the new kernel to `boot_x` and reads it back to verify,
4. shows a **“Restart to finish the update”** notification with a *Restart now* button.

To go back to the previous kernel from the tablet:

```bash
doas douglas-flash-kernel --rollback
```

If the tablet does not start after a kernel update, restore the previous kernel from TWRP —
see *If something goes wrong* in [INSTALL.md](INSTALL.md).

### Requiring a password

Installs are allowed without a password by Alpine's own polkit rules for Flatpak
(`/usr/share/polkit-1/rules.d/org.freedesktop.Flatpak.rules`) and apk
(`dev.Cogitri.apkPolkit2.rules`). To require a password, remove the desktop user from the
`wheel` group (`doas delgroup user wheel`) — then Discover asks for an administrator password.

### Where updates come from

`douglas-base` adds the project's update repository to `/etc/apk/repositories` and installs
its public signing key in `/etc/apk/keys/douglas-repo.rsa.pub`. Packages that are not signed
with the matching private key are rejected by apk.

## For maintainers: publishing an update

1. Make the change (kernel patch, config, a file in `packaging/douglas-base`, …).
2. Bump the version in the package's `APKBUILD`:
   * kernel: `packaging/douglas-kernel/APKBUILD` — `pkgver` for a new Linux version,
     otherwise increase `pkgrel`;
   * device files: `packaging/douglas-base/APKBUILD` — `pkgver`/`pkgrel`.
3. Build and test on a tablet:

   ```bash
   sudo kernel/build.sh          # only if the kernel changed
   sudo packaging/build.sh
   ```

   To test before publishing, serve `out/repo` from the PC
   (`python3 -m http.server -d out/repo 8000`) and on the tablet temporarily add
   `http://<pc-ip>:8000/alpine/v3.24/douglas` to `/etc/apk/repositories`, then
   `doas apk upgrade`.
4. Publish: `packaging/publish.sh` (update repository only) or
   `packaging/publish.sh --release` (also a GitHub Release with fresh install images).

Tablets see the update the next time Discover checks (or immediately with
*Discover → Updates → Refresh*).

**The signing key** (`~/.config/fire-hd8-linux/keys/douglas-repo.rsa`, see `config.sh`) is
created on the first `packaging/build.sh`. Back it up somewhere safe. If it is lost, installed
tablets will not accept new updates until their owners install a new public key by hand.
