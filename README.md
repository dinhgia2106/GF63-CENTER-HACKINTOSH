# R3 Control

<p align="center">
  <img src="R3Control/Assets/AppIcon.png" width="144" alt="R3 Control app icon">
</p>

Native macOS control center for the MSI GF63 Hackintosh community.

## Current build

- Real AppleSMC CPU temperature and package-power monitoring.
- CPU, memory, disk and battery status.
- Direct read-only battery telemetry from firmware `BAT1._BIX` or `_BIF`, plus `_BST`, with a macOS fallback.
- Hardware-backed 60%, 80% and 100% battery charge limits with EC read-back.
- SwiftUI dashboard and menu-bar panel.
- WidgetKit small, medium and large desktop widgets with live/stale status.
- Native Liquid Glass surfaces on macOS 26 with a Material fallback on macOS 14 and 15.
- Hardware-backed Eco+, Eco, Comfort, Sport and Turbo performance profiles with read-back.
- Hardware-backed Auto, Silent, Boost and Custom fan behaviors.
- A single 35–100% Custom speed slider; selecting Boost controls Cooler Boost directly.
- Native launch-at-login support through `SMAppService`.
- A minimal R3EC kernel bridge with an exact firmware allowlist, verified writes and automatic Firmware-Auto rollback.

The packaged ad-hoc build is available at `build/Products/R3Control.app`. Open it once so the app can publish its first hardware snapshot, then add **R3 System Status** from the macOS desktop widget gallery. Clicking the widget opens R3 Control.

The editable vector icon source is stored at `R3Control/Assets/AppIcon.svg`; Xcode compiles the generated macOS icon set from `Assets.xcassets`.

See `MACHINE_AUDIT.md` for compatibility/testing guidance and `R3EC/README.md` for the OpenCore installation and recovery procedure.

Version `0.2.5` performs real EC control only when `R3EC.kext` reads an exact `16R3EMS1.100` or `16R3EMS1.102` firmware match. Unknown firmware remains telemetry-only. The performance values are Eco `0xC2`, Comfort `0xC1`, Sport `0xC0` and Turbo `0xC4`. Eco+ combines Eco with Fan Auto, Boost off, a 15 W sustained/25 W burst Intel package-power limit and reduced app polling. Battery Care exposes only the verified 60%, 80% and 100% thresholds at EC `0xEF`; each change is read back before the app reports success. An EC value without the threshold-valid bit is treated as uninitialized and can be initialized only to one of those presets. R3EC reads capacity, state, rate and voltage directly from the firmware `BAT1._BIF/_BST` packages on MS-16R3. Because this firmware has no `_BIX` cycle-count field, the app reports cycle count as unavailable instead of copying SMCBatteryManager's synthetic wear-based value. AppleSmartBattery is used only as a fallback when direct firmware telemetry is invalid. Battery percentage is shown in every widget size whether or not AC power is connected.

## Build

Run `Scripts/build.sh` to produce the ad-hoc signed app and unsigned OpenCore kext in `build/Products`. R3EC accepts clients only from the active local login session and exposes no arbitrary EC address API.

Command-line verification:

```sh
Scripts/build.sh
```

## Safety

The AppleSMC bridge remains read-only. R3EC exposes no arbitrary address or MSR API: it permits only known commands, validates ranges, reads every write back, debounces sliders, and restores Auto with Cooler Boost off when the client disconnects. Eco+ refuses locked RAPL registers, saves the original package-power limit and restores it exactly on exit/disconnect. Charge-limit writes remain restricted to exact allowlisted firmware and the three fixed threshold bytes. Keep a known-good EFI/USB boot entry before installing any experimental kext.

## Licensing

Project code is provided under GPL-2.0-or-later. The AppleSMC structure layout in `SMCBridge.c` follows the public implementation used by smcFanControl. The MS-16R3 fan profile was cross-checked against [YoyPa/isw](https://github.com/YoyPa/isw), and the charge-threshold layout against [BeardOverflow/msi-ec](https://github.com/BeardOverflow/msi-ec).
