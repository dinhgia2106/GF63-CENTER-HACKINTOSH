# R3 Control roadmap

## 0.1 — working monitor MVP

- Native SwiftUI dashboard.
- Menu-bar status panel.
- Live AppleSMC temperature and package-power monitoring.
- CPU, memory, disk and battery monitoring.
- Small and medium WidgetKit desktop widgets.
- Read-only hardware bridge and visible safety gate.

## 0.2 — hardware identification

- Read EC firmware identity without writing.
- Capture and compare EC state in macOS and Windows/MSI Center.
- Confirm fan percentage, temperature, profile and Cooler Boost offsets on this exact unit.
- Flag invalid battery telemetry and expose raw diagnostic values.

## 0.3 — R3EC privileged bridge

- Minimal privileged helper with a fixed command allowlist.
- Exact firmware allowlist; refuse all unknown firmware.
- Masked EC writes only, followed by read-back verification.
- Rate limiting, command timeout and audit log.
- Automatic rollback to firmware Auto on disconnect, sleep, crash or thermal alarm.

## 0.4 — controlled cooling

- Auto, Silent, Advanced and Cooler Boost modes.
- Eco, Comfort, Sport and Turbo profiles.
- Per-profile fan curves after hardware validation.
- Launch at login and persistent profile restore.
- Notifications for critical temperature and bad battery state.

## Acceptance gates before enabling writes

1. Exact EC firmware is positively identified.
2. Each target register is reproduced across cold boot, sleep/wake and Windows reference captures.
3. Auto-mode rollback is tested under helper termination and app termination.
4. CPU thermal protection remains owned by firmware; the app cannot lower safety limits.
5. A recovery procedure is documented and tested.
