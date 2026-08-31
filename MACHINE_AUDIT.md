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

Version 0.1.0 is read-only at the hardware boundary. Fan, performance and charge preferences can be edited and saved locally, but no setting is written to the EC unless a future R3EC bridge positively matches a validated firmware profile. Unknown systems remain fully usable for whatever monitoring data macOS and AppleSMC expose.
