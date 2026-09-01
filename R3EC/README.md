# R3EC hardware bridge

R3EC is the privileged, firmware-gated bridge used by R3 Control. It attaches to the ACPI Embedded Controller and exposes a small user client restricted to the active local login session; it does not expose arbitrary EC addresses.

## Supported hardware

- Board family: MSI MS-16R3 / GF63 8RCS, 9RC, 9RCX and 9SC.
- Exact EC firmware allowlist: `16R3EMS1.100`, `16R3EMS1.102`.
- Unknown or unreadable firmware: telemetry only; every write returns `kIOReturnNotPermitted`.

The user-facing behaviors are Auto, Silent (`0x1D`), Boost and Custom fixed speed. Boost uses the verified Cooler Boost bit, while Custom uses the fixed-speed Basic EC mode. Battery charging and MSI Shift/performance modes are blocked.

## Safety behavior

- Every EC write is read back and verified.
- Fan-mode verification masks the firmware-owned low status bits.
- Curves are limited to six increasing 45–95°C thresholds, 35–100% output, and at least 62% at the final threshold.
- Partial curve/fixed-speed failures return to firmware Auto.
- Closing or crashing the app closes its user client and restores firmware Auto with Cooler Boost off.
- The app debounces fan sliders so dragging does not flood the EC.

## OpenCore installation

Run `Scripts/build.sh`, then copy `build/Products/R3EC.kext` to `EFI/OC/Kexts`. Add this entry under `Kernel -> Add` (or run an OC Snapshot):

| Key | Value |
| --- | --- |
| BundlePath | `R3EC.kext` |
| Enabled | `true` |
| ExecutablePath | `Contents/MacOS/R3EC` |
| PlistPath | `Contents/Info.plist` |
| Arch | `x86_64` |
| MinKernel | `25.0.0` |

Reboot, then verify without writing:

```sh
ioreg -r -c R3ECBridge -l
kmutil showloaded | grep -F com.grazt.driver.R3EC
```

Only after `firmware = 16R3EMS1.100` or `.102` and `writable = Yes` appear should hardware controls be used. Keep a known-good EFI entry or USB EFI available so `R3EC.kext` can be disabled if booting fails.
