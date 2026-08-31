# R3 Control roadmap

## 0.1 — working monitor MVP

- Native SwiftUI dashboard.
- Menu-bar status panel.
- Live AppleSMC temperature and package-power monitoring.
- CPU, memory, disk and battery monitoring.
- Small and medium WidgetKit desktop widgets.
- Read-only hardware bridge and visible safety gate.

## 0.2 — MS-16R3 hardware control

- Persistent performance, fan-mode and Cooler Boost preferences.
- Editable Advanced fan curve with monotonic point validation.
- Native launch at login.
- Read EC firmware identity before permitting writes.
- R3EC kernel bridge using the OS-serialized ACPI EC address space.
- Exact allowlist for `16R3EMS1.100` and `.102`.
- Real Auto, Basic, Advanced curve and Cooler Boost commands.
- Per-write read-back and disconnect rollback to firmware Auto.
- Capture and compare EC state in macOS and Windows/MSI Center.
- Confirm fan percentage, temperature, profile and Cooler Boost offsets on this exact unit.
- Battery charge writes are out of scope for this machine.

## 0.3 — hardening and broader validation

- Add sleep/wake integration and an in-kext thermal watchdog.
- Add a bounded audit log and kernel-side rate limiting.
- Validate Silent and MSI Shift modes with Windows reference captures.
- Add additional firmware only after per-version EC dumps and recovery testing.

## 0.4 — controlled cooling

- Auto, Basic, Advanced and Cooler Boost modes are implemented; Silent remains gated.
- Eco, Comfort, Sport and Turbo profiles.
- Per-profile fan curves after hardware validation.
- Apply saved controls explicitly through the validated R3EC bridge.
- Notifications for critical temperature and bad battery state.

## Acceptance gates before enabling writes

1. Exact EC firmware is positively identified.
2. Each target register is reproduced across cold boot, sleep/wake and Windows reference captures.
3. Auto-mode rollback is tested under helper termination and app termination.
4. CPU thermal protection remains owned by firmware; the app cannot lower safety limits.
5. A recovery procedure is documented and tested.
