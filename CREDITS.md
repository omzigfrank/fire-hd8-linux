# Credits

Fire HD 8 Linux stands on the work of many people:

* **amonet** — the bootrom exploit and unlocked bootloader for MediaTek Fire tablets, by
  xyz` and k4y0z, with the douglas port collected at
  <https://github.com/ryanfortner/FireHD8-2017>. Not included here; required for installing.
* **MT8163 mainline support** — bengris32's `linux-f` (branch `mt8163/7.0`), the basis of
  the platform patches (clocks, pinctrl, power domains, display, audio front end, DT), and
  the upstream MT8163 work it builds on.
* **MT6625L Wi-Fi/Bluetooth driver** — MediaTek's gen2 connectivity stack as published in
  Amazon's GPL kernel source for douglas (`mt8163-dev/android_kernel_amazon_mt8163`) and
  frank-w's port for the BananaPi R2 (`frank-w/BPI-Router-Linux`, branch `6.0-mt6625`).
  The WMT userspace tools (`wmt_loader`, `stp_uart_launcher`) are from
  `frank-w/BPI-R2-4.14`, `utils/wmt`.
* **Terminus font** (boot splash), by Dimitar Zhekov, as included in Linux
  (`lib/fonts/font_ter16x32.c`).
* **Alpine Linux**, **KDE Plasma Mobile**, **Mesa/Panfrost** and the Linux kernel community.

Board bring-up, the douglas device tree, the SMP/SPM, sleep, audio codec, display zero-copy
and Wi-Fi porting changes, the boot shim and the packaging in this repository were written
for this project.
