# GF63 compatibility and testing notes

R3 Control is intended for the MSI GF63 family rather than one specific unit. GF63 revisions can use different CPUs, GPUs, Embedded Controller firmware and sensor layouts, so every capability is detected at runtime.

## Runtime detection

- CPU model, core topology, macOS version, architecture and disk capacity are read from the current system.
- AppleSMC temperature, package-power and fan keys are treated as optional capabilities.
- Battery information is displayed only when macOS reports a portable power source.
- Missing data is shown as unavailable instead of being replaced with sample values from a development machine.
- Battery warnings appear only when the current telemetry is invalid or internally inconsistent.

## Compatibility model

Monitoring should degrade gracefully across GF63 configurations. A missing fan key does not disable CPU, memory, disk or battery monitoring. Likewise, missing battery telemetry does not create a permanent warning on systems where that sensor path is unavailable.

Hardware controls require a separate firmware profile. Each profile must identify at least:

- GF63 board or product variant.
- Exact EC firmware revision.
- Verified temperature and fan telemetry offsets.
- Verified fan mode, performance profile and Cooler Boost masks.
- A tested firmware-Auto recovery path.

No register address discovered on one GF63 unit may be assumed safe on another revision.

## Contributor test report

When reporting compatibility, include non-unique information only:

- GF63 marketing model and motherboard family.
- EC firmware revision.
- CPU and GPU model.
- macOS and OpenCore versions.
- VirtualSMC plugin versions.
- Which metrics are available or missing.

Do not publish serial numbers, MAC addresses, MLB/ROM values or other unique SMBIOS identity data.

## Current safety boundary

Version 0.2.0 includes real control for MS-16R3 only. `R3EC.kext` reads the EC identity from `0xA0...0xAB` and enables its fixed command allowlist only for `16R3EMS1.100` and `16R3EMS1.102`. Unknown firmware remains monitor-only.

Supported user-facing controls are CPU fan Auto, Silent, Boost and Custom fixed speed, plus Eco+, Eco, Comfort, Sport and Turbo performance profiles. Eco+ is limited to an unlocked Intel RAPL package-power register, PL1 15 W and PL2 25 W; it does not apply a voltage offset. Battery charging, arbitrary EC/MSR access and unknown firmware are blocked. Each write is verified; closing/crashing restores the original package-power limit, fan Auto, Cooler Boost off and Comfort.
