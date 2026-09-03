# R3 Control roadmap

## 0.1 — working monitor MVP

- Native SwiftUI dashboard.
- Menu-bar status panel.
- Live AppleSMC temperature and package-power monitoring.
- CPU, memory, disk and battery monitoring.
- Small and medium WidgetKit desktop widgets.
- Read-only hardware bridge and visible safety gate.

## 0.2 — MS-16R3 hardware control

- Persistent performance and fan-behavior preferences.
- Single fixed-speed slider for Custom behavior.
- Native launch at login.
- Read EC firmware identity before permitting writes.
- R3EC kernel bridge using the OS-serialized ACPI EC address space.
- Exact allowlist for `16R3EMS1.100` and `.102`.
- Real Auto, Silent, Boost and Custom fixed-speed commands.
- Eco+ with verified/restorable 15 W PL1 and 25 W PL2 package limits.
- Battery Care presets at 60%, 80% and 100%, gated by the EC threshold-valid bit and verified by read-back.
- Per-write read-back and disconnect rollback to firmware Auto.
- Capture and compare EC state in macOS and Windows/MSI Center.
- Confirm fan percentage, temperature, performance profile and Cooler Boost offsets on this exact unit.

## 0.3 — hardening and broader validation

- Add sleep/wake integration and an in-kext thermal watchdog.
- Add a bounded audit log and kernel-side rate limiting.
- Expand performance controls only after exact-firmware validation.
- Add additional firmware only after per-version EC dumps and recovery testing.

## 0.4 — controlled cooling

- Auto, Silent, Boost and Custom fan behaviors are implemented.
- Eco+, Eco, Comfort, Sport and Turbo profiles.
- Apply saved controls explicitly through the validated R3EC bridge.
- Notifications for critical temperature and bad battery state.

## Acceptance gates before enabling writes

1. Exact EC firmware is positively identified.
2. Each target register is reproduced across cold boot, sleep/wake and Windows reference captures.
3. Auto-mode rollback is tested under helper termination and app termination.
4. CPU thermal protection remains owned by firmware; the app cannot lower safety limits.
5. A recovery procedure is documented and tested.
