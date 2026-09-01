# R3 Control

<p align="center">
  <img src="R3Control/Assets/AppIcon.png" width="144" alt="R3 Control app icon">
</p>

Native macOS control center for the MSI GF63 Hackintosh community.

## Current build

- Real AppleSMC CPU temperature and package-power monitoring.
- CPU, memory, disk and battery status.
- SwiftUI dashboard and menu-bar panel.
- WidgetKit small and medium desktop widgets.
- Native Liquid Glass surfaces on macOS 26 with a Material fallback on macOS 14 and 15.
- Persistent Eco, Comfort, Sport and Turbo app presets with hardware-backed Auto, Silent, Boost and Custom fan behaviors.
- A single 35–100% Custom speed slider; selecting Boost controls Cooler Boost directly.
- Native launch-at-login support through `SMAppService`.
- A minimal R3EC kernel bridge with an exact firmware allowlist, verified writes and automatic Firmware-Auto rollback.

The packaged ad-hoc build is available at `Build/R3Control.app`. Open it once, then add **R3 System Status** from the macOS desktop widget gallery.

The editable vector icon source is stored at `R3Control/Assets/AppIcon.svg`; Xcode compiles the generated macOS icon set from `Assets.xcassets`.

See `MACHINE_AUDIT.md` for compatibility/testing guidance and `R3EC/README.md` for the OpenCore installation and recovery procedure.

Version `0.2.0` performs real EC control only when `R3EC.kext` reads an exact `16R3EMS1.100` or `16R3EMS1.102` firmware match. Unknown firmware remains telemetry-only. Battery charging and MSI Shift/performance registers are intentionally not written; their controls are omitted or labelled as local presets.

## Build

Run `Scripts/build.sh` to produce the ad-hoc signed app and unsigned OpenCore kext in `build/Products`. R3EC accepts clients only from the active local login session and exposes no arbitrary EC address API.

Command-line verification:

```sh
Scripts/build.sh
```

## Safety

The AppleSMC bridge remains read-only. R3EC exposes no arbitrary address API: it permits only known commands, validates ranges, reads every write back, debounces sliders, and restores Auto with Cooler Boost off when the client disconnects. Keep a known-good EFI/USB boot entry before installing any experimental kext.

## Licensing

Project code is provided under GPL-2.0-or-later. The AppleSMC structure layout in `SMCBridge.c` follows the public implementation used by smcFanControl. The MS-16R3 fan profile was cross-checked against [YoyPa/isw](https://github.com/YoyPa/isw).
