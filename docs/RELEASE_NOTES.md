Fire HD 8 Linux for the Amazon Fire HD 8 **2017 (7th generation, KFDOWI, "douglas") only**.

**Install:** unlock with amonet, boot TWRP, then run `./install.sh boot.img rootfs.img.gz`
— see [docs/INSTALL.md](https://github.com/OWNER/REPO/blob/main/docs/INSTALL.md).
Installing erases all Fire OS user data.

**Already installed?** You get this through Discover → Updates.

Contents
* Linux 7.3.4 with MT8163 platform support, GPU (Panfrost), Wi-Fi/Bluetooth (MT6625L),
  sound, sleep (s2idle), zero-copy display
* Alpine Linux 3.24 with KDE Plasma Mobile, Firefox, LibreOffice (Writer, Calc, Impress),
  Okular, Discover with Flathub
* Over-the-air updates for the system and the kernel

Check downloads with `sha256sum -c SHA256SUMS`.
