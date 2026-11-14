# Fire HD 8 Linux

Mainline Linux and a touch-friendly desktop (KDE Plasma Mobile on Alpine Linux) for the
**Amazon Fire HD 8, 7th generation (2017)** — model KFDOWI, codename `douglas`, MediaTek MT8163.

It turns the tablet into a simple, general-purpose tablet: web browser, office apps, PDF
reader, an app store, and system updates delivered over Wi-Fi.

> **Only for the Fire HD 8 2017 (KFDOWI / douglas).** Other Fire tablets, including other
> Fire HD 8 generations, use different hardware and will not boot this.
> Installing erases all Fire OS user data. You need to unlock the bootloader first, which
> has its own risks. You do this at your own risk.

## What works

| | |
|---|---|
| Display, touch, brightness, auto-rotate | ✅ GPU-accelerated (Mali-T720 via Panfrost) |
| Wi-Fi 2.4/5 GHz, Bluetooth (incl. audio) | ✅ needs the tablet's own firmware (copied from Fire OS automatically) |
| Speaker, headphones, microphone | ✅ headphone output is switched manually (no jack detection yet) |
| Battery, charging, power/volume keys | ✅ |
| Sleep | ⚠️ suspend-to-idle only (screen off, CPUs idle); uses more battery than Fire OS |
| All 4 CPU cores, frequency scaling, thermal limits | ✅ |
| microSD | ❓ driver loads, not tested with a card |
| Cameras, hardware video decoding | ❌ no mainline drivers |

See [docs/HARDWARE.md](docs/HARDWARE.md) for details.

## Install

1. Unlock the bootloader with **amonet** for douglas and get TWRP on `recovery_x` —
   follow the original guide (linked in [docs/INSTALL.md](docs/INSTALL.md)).
2. Download `boot.img`, `rootfs.img.gz` and `install.sh` from the
   [latest release](../../releases/latest).
3. Boot TWRP, connect USB, and run `./install.sh boot.img rootfs.img.gz`.

Full instructions, including backups and recovery: **[docs/INSTALL.md](docs/INSTALL.md)**.

## Updates

Installed tablets get updates over the air. **Discover** (the app store) shows system and app
updates; a kernel update is written automatically and the tablet asks you to restart.
The previous kernel is kept so it can be restored. See [docs/UPDATES.md](docs/UPDATES.md).

## Build it yourself

`kernel/` (patches against Linux 7.3.4, config, boot image tools), `packaging/` (the
over-the-air packages) and `rootfs/` (the system image). See [docs/BUILDING.md](docs/BUILDING.md).

## Credits and licences

This builds on a lot of other people's work — see [CREDITS.md](CREDITS.md).
Kernel patches are GPL-2.0; everything else is MIT unless a file says otherwise
(see [LICENSE](LICENSE)). Proprietary firmware is **not** included: it is copied from each
tablet's own Fire OS system partition on first boot.
