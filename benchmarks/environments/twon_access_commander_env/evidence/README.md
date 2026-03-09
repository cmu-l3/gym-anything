# 2N Access Commander Environment — Evidence Documentation

## Summary

This document records the testing results for `twon_access_commander_env`.
Testing was run on 2026-02-22 using live QEMU VMs (most recently SSH:2349, VNC:6097).

**Important**: The 2N Access Commander OVA was **not present** during testing (it must be
obtained separately from the 2N download center — see OVA Requirement section below).
Screenshots show Firefox's "Unable to connect" error at `localhost:9443` because the inner
VM was not running. This is expected and documented behavior. The scripts, task setups,
and URL routing were designed based on the 2N AC v3 REST API and web UI specification.

**Nested KVM is confirmed available on the test host**: The outer VM's syslog shows
`kvm: Nested Virtualization enabled` and `SVM: Nested Paging enabled`. When the OVA is
present, the inner VM will boot with KVM hardware acceleration (~5 min), not TCG emulation.

---

## Verification Checklist

| Check | Status | Notes |
|-------|--------|-------|
| Installation script completes without errors | ✅ PASS | Firefox 146.0 + QEMU 6.2.0 installed |
| Setup script handles missing OVA gracefully | ✅ PASS | Prints clear warning, exits cleanly |
| Firefox launches to correct URL (localhost:9443) | ✅ PASS | Confirmed via VNC + visual_grounding |
| Task setup scripts source task_utils.sh correctly | ✅ PASS | No import errors |
| Verifier.py stubs (VLM verification is external) | ✅ PASS | All 10 stubs return `{"passed": True}` |
| Realistic data seeding script present | ✅ PASS | 25 employees, 5 groups, 4 time profiles |
| navigate_access_logs URL consistent (/#/accessLog) | ✅ PASS | Fixed: setup_task.sh and task.json match |
| Card credential format consistent across scripts | ✅ PASS | Fixed: `type=card, cardNumber=...` everywhere |
| KVM availability check with TCG fallback | ✅ PASS | setup_twon_ac.sh checks /dev/kvm |
| TCG extended timeout (3600s vs 300s) | ✅ PASS | setup_twon_ac.sh sets TIMEOUT=3600 for TCG |
| No unused mounts in env.json | ✅ PASS | Empty config/ mount removed |
| DBUS_SESSION_BUS_ADDRESS set for snap Firefox | ✅ PASS | Added to launch_firefox_to in task_utils.sh |
| create_time_profile uses unique name (no seed conflict) | ✅ PASS | Changed to "Weekend Access" (Sat-Sun 09:00-17:00) |
| add_user_to_group clarifies pre-condition | ✅ PASS | Task description notes Sandra not yet in group |
| **Application running and task UI verified** | ⚠️ PENDING | **Requires OVA at data/access_commander.ova** |

---

## Pre-start Hook Log (tail) — Actual Output

```
...
Requirement already satisfied: requests in /usr/lib/python3/dist-packages (2.25.1)
=== 2N Access Commander prerequisites installed ===
Firefox: Mozilla Firefox 146.0
QEMU: QEMU emulator version 6.2.0 (Debian 1:6.2+dfsg-2ubuntu6.27)
```

**Packages installed**: wmctrl, xdotool, x11-utils, xclip, curl, jq, ca-certificates, netcat-openbsd,
python3, python3-pip, scrot, imagemagick, wget, net-tools, firefox, libnss3-tools,
qemu-system-x86, qemu-utils, ovmf, bridge-utils, cpu-checker

---

## Post-start Hook Log — Actual Output (without OVA)

```
=== Setting up 2N Access Commander (nested QEMU) ===
WARNING: OVA not found at /workspace/data/access_commander.ova
Place the 2N Access Commander OVA at that path before starting.
Setting up Firefox profile pointing to local AC (will work once OVA is present).
[GTK warnings about canberra-gtk-module — HARMLESS]
=== Setup complete (no OVA — Firefox opened to AC URL) ===
AC URL: https://localhost:9443 (inner VM not running)
```

**Expected flow when OVA is present**:
1. OVA extracted → VMDK converted to QCOW2
2. Inner QEMU VM launched (KVM if available → ~5 min boot; TCG fallback → 30-60 min boot)
3. Wait up to 300s (KVM) or 3600s (TCG) for AC to respond on localhost:9443
4. Seed 25 users / 5 groups / 4 time profiles via REST API
5. Configure Firefox profile and pre-accept self-signed TLS cert
6. Launch Firefox to AC login page

---

## Screenshot Evidence

### Screenshot Explanation

All screenshots show Firefox's "Unable to connect" error at `localhost:9443` because the
OVA was not present — the inner VM never started. The screenshots confirm:

1. Firefox launched correctly under the `ga` user via the snap profile path
2. The pre_task hook ran and navigated Firefox to the correct task-specific URL
3. The DBUS_SESSION_BUS_ADDRESS env var is set (snap Firefox compatibility)

**New screenshot**: `task01_create_user_pretask_hook.png` — captured 2026-02-22 on SSH:2349.
Shows Firefox at `localhost:9443/#/users`, confirming the `create_user` pre_task hook ran
successfully and navigated to the correct URL.

**These screenshots do NOT confirm that the 2N AC application loaded or that task UIs
were verified against a live system.** Full verification requires the OVA.

### Task URL Table

The following URLs are used by each task's `setup_task.sh` (based on 2N AC v3 web UI):

| # | Task | URL | Screenshot |
|---|------|-----|-----------|
| 1 | create_user | `localhost:9443/#/users` | `task01_create_user_url.png` |
| 2 | assign_rfid_card | `localhost:9443/#/users/{id}` | `task02_assign_rfid_card_url.png` |
| 3 | create_user_group | `localhost:9443/#/groups` | `task03_create_user_group_url.png` |
| 4 | add_user_to_group | `localhost:9443/#/groups` | `task04_add_user_to_group_url.png` |
| 5 | set_user_pin | `localhost:9443/#/users/{id}` | `task05_set_user_pin_url.png` |
| 6 | create_time_profile | `localhost:9443/#/timeProfiles` | `task06_create_time_profile_url.png` |
| 7 | navigate_access_logs | `localhost:9443/#/accessLog` | `task07_navigate_access_logs_url.png` |
| 8 | update_user_email | `localhost:9443/#/users/{id}` | `task08_update_user_email_url.png` |
| 9 | disable_user | `localhost:9443/#/users/{id}` | `task09_disable_user_url.png` |
| 10 | remove_card_from_user | `localhost:9443/#/users/{id}` | `task10_remove_card_from_user_url.png` |

---

## OVA Requirement

The 2N Access Commander OVA **must be obtained separately** and placed at:
```
benchmarks/environments/twon_access_commander_env/data/access_commander.ova
```

**Download**: https://www.2n.com/en-GB/download-center/?product=2n-access-commander
**Section**: Software & Firmware
**License**: Free "Lite" tier available (1 device, 5 users) — sufficient for benchmark tasks

The OVA cannot be downloaded automatically:
- The 2N download center requires user registration
- acdemo.2n.com (online demo) requires server-side reCAPTCHA validation that cannot be bypassed

---

## Realistic Pre-seeded Data

The `seed_ac_data.py` script creates a realistic mid-size commercial building tenant population.
Data is seeded via REST API after the inner VM becomes reachable.

### User Groups (5)
- Employees (12 members — BuildingTech Solutions)
- Contractors (3 members — Meridian Facilities)
- Security Staff (3 members — SecureGuard Services)
- Reception Team (2 members)
- IT Department (2 members)

### Time Profiles (4)
- **Office Hours**: Mon-Fri 08:00-18:00
- **Extended Hours**: Mon-Fri 06:00-22:00
- **24/7 Access**: All days 00:00-23:59
- **Contractor Hours**: Mon-Fri 09:00-17:00

### Sample Employees (25 total)
```
Sandra Okafor      - Reception Team    - card: 0004521873
Derek Caldwell     - Employees         - card: 0013988412  (assign_rfid_card task target)
Priya Nair         - Employees         - card: 0004521875  (update_user_email task target)
Victor Schulz      - Security Staff    - card: 0004521887  (disable_user task target)
Leon Fischer       - Security Staff    - card: 0007654321  (remove_card_from_user task target)
Marcus Webb        - Employees         - card: 0004521876  (set_user_pin task target)
Nadia Ivanova      - Contractors       - card: 0004521890
... (18 more employees across all groups)
```

All names are professionally diverse. RFID cards use 10-digit numeric format (HID Prox-compatible).

---

## API Design Notes

The REST API calls across all scripts use consistent field naming:
- **Card credentials**: `{"type": "card", "cardNumber": "<10-digit>"}` — consistent in both
  `seed_ac_data.py` and `remove_card_from_user/setup_task.sh`
- **Auth**: `PUT /api/v3/auth` with `{"login":"admin","password":"2n"}`
- **Users**: `POST /api/v3/users`, `GET /api/v3/users`, `DELETE /api/v3/users/{id}`
- **Groups**: `POST /api/v3/groups`, `POST /api/v3/groups/{id}/members`

---

## Why Not Full API Verifiers

Per `env_creation_notes/prompt.md`: "Verification is handled externally via VLM evaluators.
The verifier.py file is a stub kept for framework compatibility."

All 10 `verifier.py` files are stubs returning `{"passed": True, "score": 100}`.
