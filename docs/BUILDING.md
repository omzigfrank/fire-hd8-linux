# Building

Everything builds on an x86_64 Linux host (Debian/Ubuntu, or WSL2 on Windows). ARM64
userspace parts are built natively in an Alpine aarch64 chroot through qemu-user.

## Host packages (Debian/Ubuntu)

```bash
sudo apt install build-essential bc bison flex libssl-dev libelf-dev cpio python3 curl \
    xz-utils gcc-aarch64-linux-gnu qemu-user-static binfmt-support e2fsprogs git
```

About 15 GB of free disk space is needed under `build/`.

## Steps

```bash
sudo kernel/build.sh      # -> out/boot.img            (Linux 7.3.4 + patches)
sudo packaging/build.sh   # -> out/repo/…              (signed douglas-base, douglas-kernel)
sudo rootfs/build.sh      # -> out/rootfs.img.gz       (Alpine + Plasma Mobile)
```

Settings (GitHub repository, update URL, Alpine version, key location) are in `config.sh`.
Set `GITHUB_REPO=owner/name` before building packages for your own fork, so tablets look for
updates in your repository.

## Layout

| Path | What |
|---|---|
| `kernel/patches/` | patches against vanilla Linux 7.3.4 (MT8163 platform, board DT, drivers) |
| `kernel/config/douglas_defconfig` | kernel configuration |
| `kernel/boot/` | `mkboot.py` (boot image for the stock LK) and the relocation shim |
| `kernel/initramfs/init` | finds the system on `userdata`, splash, rescue shell |
| `packaging/douglas-base/` | device support package: Wi-Fi/BT tools, services, sound profile, sleep hooks, tuning, first-boot setup, update notifier |
| `packaging/douglas-kernel/` | kernel package that flashes `boot_x` on install |
| `rootfs/` | package list and image builder |
| `tools/install.sh` | installer (PC side, adb + TWRP) |

## Boot constraints of the stock bootloader

* It decompresses the kernel to `0x40080000`; modern arm64 kernels need a 2 MiB aligned base,
  so `kernel/boot/relocate-kernel.S` (4 KiB) moves the Image to `0x40200000` first.
* It silently hangs at the Amazon logo if the decompressed kernel exceeds about 28 MiB;
  `mkboot.py` refuses payloads above `0x1bf0000`. Keep the config trim (`=y` drivers only for
  this board; no modules are used).
* It patches the appended DTB in place, so the DTB gets 64 KiB of slack.
* The display is the framebuffer the bootloader left running; the kernel keeps scanning out
  from it (simpledrm) and points the display controller straight at the compositor's
  buffers (zero-copy), with the GPU (Panfrost) doing the rendering.

## Kernel patches

`kernel/patches/` is generated from a working tree with `diff -urN` against vanilla 7.3.4 and
split by area. To change the kernel, apply the patches to a fresh tree, edit, and regenerate
the affected patch (`git diff` in a tree where you committed vanilla first is easiest).
