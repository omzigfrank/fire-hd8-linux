# Hardware support

Fire HD 8 (2017, `douglas`): MediaTek MT8163 (4× Cortex-A53 up to 1.3 GHz, Mali-T720 MP2),
1.5 GB RAM, 16/32 GB eMMC, 800×1280 NT35521 DSI panel, Goodix GT9110 touch,
MT6625L Wi-Fi/Bluetooth/FM combo, MT6323 PMIC, BMA253 accelerometer.

| Component | Status | Notes |
|---|---|---|
| CPU, SMP | ✅ | secondaries started with PSCI 0.1 CPU_ON plus the SPM power-on sequence from Amazon's kernel (`arch/arm64/kernel/psci.c`, douglas only) |
| CPU frequency / thermal | ✅ | 600 MHz–1.3 GHz, cpufreq cooling at 80 °C |
| eMMC | ✅ | HS200 |
| Display | ✅ | the bootloader's framebuffer via simpledrm; zero-copy scanout by pointing DISP_OVL0 layer 3 at the compositor buffer; no native DSI driver (SMI/larb clocks missing) |
| Backlight | ✅ | display PWM; GPIO43 must stay high or the panel loses its state |
| GPU | ✅ | Panfrost (OpenGL ES 2.0 / Mali-T720) |
| Touch | ✅ | Goodix GT9110, uses the configuration already stored in the touch chip |
| Wi-Fi | ✅ | MediaTek gen2 (MT6625L) driver ported from Amazon's and frank-w's kernels; firmware and NVRAM come from the tablet's own Fire OS |
| Bluetooth | ✅ | native BlueZ `hci0` on the same combo chip; A2DP audio works |
| Speaker, headphones | ✅ | MT6323 codec + MT8163 AFE; ALSA UCM profile `douglas`; no jack detection (switch output manually) |
| Microphone | ✅ | analog main mic |
| Battery, charger | ✅ | bq24297 charger, MT6323 fuel gauge with Amazon's OCV table |
| Keys | ✅ | power, volume up/down |
| Accelerometer / auto-rotate | ✅ | BMA253 via iio-sensor-proxy |
| Sleep | ⚠️ | suspend-to-idle (s2idle) with RTC and power-key wake; there is no deep suspend, so standby drains faster than Fire OS |
| microSD | ❓ | driver and card-detect probe; untested with a card |
| Ambient light sensor | ❓ | JSA1212 driver present; untested |
| Cameras | ❌ | no mainline MT8163 camera (SENINF/ISP) driver |
| Video decode | ❌ | no mainline MT8163 VCODEC support; video plays in software |
| Headphone jack detection | ❌ | ACCDET not implemented |

## Known quirks

* **Wi-Fi MAC address** comes from the Fire OS NVRAM backup; the driver cannot change it, so
  NetworkManager's MAC randomisation is turned off for `mt6625_0`.
* After waking from sleep, Wi-Fi can take up to a minute to reconnect, more often while
  Bluetooth audio is in use (shared chip).
* The USB serial gadget (`ttyGS0`) is always present; the root shell on it is a developer
  option (`douglas-usbshell` service, off by default).
* Kernel size is limited to ~28 MiB decompressed by the stock bootloader.
* **Your own boot picture:** put a raw 800×1280 XRGB8888 image (little-endian, 4 096 000
  bytes) at `/etc/douglas/splash.bgrx` and a gzip of it at `/etc/douglas/splash.bgrx.gz`;
  they take precedence over the default and survive updates.
