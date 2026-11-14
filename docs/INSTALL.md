# Installing Fire HD 8 Linux

**Device:** Amazon Fire HD 8, 7th generation (2017), model KFDOWI, codename `douglas`.
Check *Settings → Device Options → About Fire Tablet* on Fire OS before you start.

**This erases all Fire OS user data** (apps, accounts, photos, downloads). Copy anything you
want to keep off the tablet first. The Fire OS *system* partition is left alone — Linux reads
the Wi-Fi/Bluetooth firmware from it — but you will not be able to boot Fire OS normally
afterwards without restoring a backup.

## 1. Unlock the bootloader (amonet)

Fire HD 8 Linux needs the tablet unlocked with **amonet**, the bootrom exploit for MT8163
Fire tablets, which installs a patched bootloader, TWRP on `recovery_x`, and boots kernels
from `boot_x`. This project does not include or modify amonet; follow its own guide:

* amonet for the Fire HD 8 2017 (douglas): <https://github.com/ryanfortner/FireHD8-2017>
  (and the XDA thread linked from there)

Some tablets need a temporary hardware short (a wire touching a test point) to enter bootrom
mode. Read the whole guide before starting. When you are done you should be able to boot
**TWRP** (recovery).

## 2. Download the release

From the [latest release](../../../releases/latest) download:

* `boot.img` — the kernel
* `rootfs.img.gz` — the system (about 1–1.5 GB)
* `install.sh` — the installer
* `SHA256SUMS` — check the downloads: `sha256sum -c SHA256SUMS`

You also need **adb** (Android platform-tools) on your PC. On Windows run the installer from
*Git Bash* or *WSL*.

## 3. Install

1. Boot the tablet into TWRP and connect it to the PC with a USB cable.
2. Check that `adb devices` lists it as `recovery`.
3. Run:

   ```bash
   chmod +x install.sh
   ./install.sh boot.img rootfs.img.gz
   ```

The installer

* checks that the device is a douglas in TWRP and that the images fit,
* **backs up** Fire OS's `/data/nvram` (the tablet's own Wi-Fi calibration and MAC address)
  and the current `boot_x` into a `douglas-backup-…` folder on your PC — keep it,
* also leaves the NVRAM backup on the tablet's `cache` partition, where Linux finds it,
* asks you to type `YES`, then writes and verifies the system and the kernel, and reboots.

> If you already wiped `/data` before (for example during the amonet process), the NVRAM
> is gone and Wi-Fi may not start. If you have a `douglas-nvram.tgz` from an earlier install,
> `adb push douglas-nvram.tgz /cache/` before running the installer.

## 4. First boot

The first boot takes a minute longer: the filesystem is grown to fill the partition and the
Wi-Fi firmware is copied from Fire OS. Then Plasma Mobile starts and a welcome dialog asks
you to **choose a PIN**. Until you do, the PIN is **1234**.

* Wi-Fi: swipe down from the top and tap the Wi-Fi tile.
* Apps: open **Discover** to install more (Flathub has Brave, Chromium, VLC, games, …).
* Updates: Discover → *Updates*. See [UPDATES.md](UPDATES.md).

## If something goes wrong

* **Stuck at the Amazon logo / black screen after an update:** hold Power ~10 s to turn off,
  then boot TWRP (the amonet key combination) and restore the previous kernel:

  ```bash
  adb shell 'mount /data; ls -d /dev/block/platform/*/by-name'
  # use the by-name directory that contains boot_x, usually /dev/block/platform/mtk-msdc.0/by-name
  adb shell 'dd if=/data/var/lib/douglas/boot_x.previous.img of=/dev/block/platform/mtk-msdc.0/by-name/boot_x'
  ```

  Or write the `boot_x.img` from your backup folder:
  `adb exec-in "dd of=/dev/block/platform/mtk-msdc.0/by-name/boot_x" < boot_x.img`.
  Then `adb reboot`.
* **Rescue shell:** if the kernel starts but cannot find the system, it opens a root shell
  on the USB serial port (it shows up as a serial/COM port on the PC, 115200 baud).
* **Back to Fire OS:** restore your TWRP backup of `boot_x`/`userdata`, or follow the
  amonet guide's instructions for returning to stock.
