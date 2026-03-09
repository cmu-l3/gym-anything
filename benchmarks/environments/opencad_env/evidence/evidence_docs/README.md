# OpenCAD Environment - Testing Evidence

## Environment Details
- **Environment ID**: `opencad_env@0.1`
- **Base Image**: `ubuntu-gnome-systemd_highres` (1920x1080)
- **Application**: OpenCAD v0.3.2 (Computer Aided Dispatch)
- **Docker Services**: MySQL 5.7 (`opencad-db`) + PHP 7.3 Apache (`opencad-app`)
- **Admin Credentials**: `admin@opencad.local` / `Admin123!`
- **Database**: MySQL `opencad` (user: `opencad`, password: `opencadpass`)

## Tasks

### Original Tasks (easy/medium)
1. **create_dispatch_call** - Create a 10-50 dispatch call at Vinewood/Alta
2. **register_civilian** - Register Wade Hebert as civilian
3. **create_bolo_vehicle** - Create a vehicle BOLO for red Bravado Buffalo
4. **approve_pending_user** - Approve Sarah Mitchell's account
5. **lookup_ncic_name** - Look up Trevor Philips and issue a citation

### New Tasks (very_hard — added 2026-03-03)
6. **fugitive_traffic_stop** - Police Dispatcher: create 10-38 call, citation for Franklin Clinton, person BOLO for fleeing passenger
7. **armed_robbery_response** - Senior Police Dispatcher: create 10-31 call, vehicle BOLO (RPZ-7851), person BOLO, warrant for Trevor Philips
8. **new_resident_full_processing** - NCIC Records Technician: register Lamar Davis, link vehicle (LAM-8844), add warrant
9. **major_incident_documentation** - Incident Commander: create 10-70 fire call, citation for Michael De Santa, person BOLO
10. **multi_jurisdiction_pursuit** - Communications Center Supervisor: create 10-80 pursuit call, vehicle BOLO (BLC-4491), warrant + citation for Trevor Philips

## Interactive Testing Evidence (Phase 6)

### Login Flow
| Screenshot | Description |
|---|---|
| `01_login_page.png` | OpenCAD login page at `http://localhost/index.php` showing email/password fields and "OpenCAD Version 0.3.2" |
| `02_dashboard_after_login.png` | Dashboard after login showing "Hello! What would you like to do today?" with ADMIN button |

### Admin Panel
| Screenshot | Description |
|---|---|
| `03_admin_panel.png` | Admin panel showing Total Users=5, pending access requests for Sarah Mitchell (3A-15) and James Rodriguez (4B-22) |

### Dispatch Access (Bug Fix Verification)
| Screenshot | Description |
|---|---|
| `04_dashboard_with_dispatch.png` | Dashboard showing ADMIN, DISPATCH, POLICE DEPARTMENT buttons (after department assignment fix) |
| `05_cad_dispatch_page.png` | Full CAD dispatch page: Active Calls (empty), Active BOLOs (1 person + 1 vehicle), Dispatchers (1A-01), New Call button |

### Task: create_dispatch_call
| Screenshot | Description |
|---|---|
| `06_new_call_dialog.png` | New Call dialog: Incident Type dropdown, Street fields, Narrative textarea, Send/Reset/Close buttons |
| `07_new_call_filled.png` | Filled form: Incident Type=10-50 Vehicle Accident, Street 1=Vinewood Boulevard, Street 2=Alta Street, Narrative describes three-vehicle collision with injuries |
| `08_dispatch_call_created.png` | Active call visible: Call ID 1, Type 10-50 Vehicle Accident, Location Vinewood Boulevard/Alta Street, Status Unassigned |

### Clean Restart Test (Phase 7.1)
| Screenshot | Description |
|---|---|
| `09_clean_restart_login.png` | Fresh restart: OpenCAD login page loads correctly after `from_config()` + `env.reset(use_cache=False)` |
| `10_clean_restart_call_created.png` | Dispatch call created on clean restart: Call ID 1, type 10-50 Vehicle Accident, Vinewood/Alta |

## Verification Pipeline Evidence

### Export Result (`verification_result.json`)
```json
{
    "initial_call_count": 0,
    "current_call_count": 1,
    "call_found": true,
    "call": {
        "id": "1",
        "type": "10-50 | Vehicle Accident",
        "street1": "Vinewood Boulevard",
        "street2": "Alta Street",
        "narrative": "THREE-VEHICLE ACCIDENT AT VINEWOOD AND ALTA. ONE VEHICLE OVERTURNED WITH MULTIPLE INJURIES REPORTED. EMS BACKUP REQUESTED. TRAFFIC BLOCKED IN BOTH DIRECTIONS."
    }
}
```

### Verifier Score (Clean Restart Run)
- **Score**: 100/100 (Passed)
- **Breakdown**:
  - Call found in database: 20/20
  - Call type matches (10-50): 20/20
  - Street 1 matches (Vinewood Boulevard): 15/15
  - Street 2 matches (Alta Street): 15/15
  - Narrative keywords (4/4 matched): 20/20
  - New call record confirmed: 10/10

### Database Verification
```
call_id=1, call_type='10-50 | Vehicle Accident', street1='Vinewood Boulevard', street2='Alta Street'
```

## Bugs Found and Fixed During Testing

### Bug: Department Access Denied on CAD Dispatch Page
- **Problem**: After login, navigating to `cad.php` showed "You do not have permission to be here"
- **Root Cause**: `user_departments` table was empty. OpenCAD's `dashboard.php` sets `$_SESSION['dispatch']='YES'` only when `department_id==1` (Communications) exists for the user
- **Fix**: Added SQL inserts to `setup_opencad.sh` section 3c:
  ```sql
  INSERT INTO user_departments (user_id, department_id) VALUES (2, 1), (2, 5), (3, 1);
  INSERT INTO user_departments_temp (user_id, department_id) VALUES (2, 1), (2, 5), (3, 1);
  ```
- **Verification**: After fix, dashboard shows DISPATCH button and cad.php loads correctly

### Bug: Session Caching After DB Change
- **Problem**: After adding department rows directly to DB, cad.php still showed "no permission"
- **Root Cause**: PHP session cached old values from initial login
- **Fix**: Navigate to dashboard.php first to trigger session variable refresh, then access cad.php

## Setup Log Evidence

### Log Files
- `pre_start_log_excerpt.txt` - Installation log (366 lines total)
- `post_start_log_excerpt.txt` - Setup log (460 lines total)
- `pre_task_log_excerpt.txt` - Task setup log (2121 lines total)

### pre_start hook (install_opencad.sh)
- Installs Docker + docker-compose
- Pulls mysql:5.7 and php:7.3-apache images
- Clones OpenCAD source to /opt/opencad-src
- **Final output**: `=== OpenCAD installation complete ===`

### post_start hook (setup_opencad.sh)
Milestone log output (from actual run):
```
=== Setting up OpenCAD ===
=== Waiting for MySQL ===
=== Verifying database ===
=== Importing official OpenCAD schema ===
=== Importing GTAV game data ===
=== Importing seed data ===
=== Configuring OpenCAD PHP application ===
=== Creating users with bcrypt passwords ===
=== Assigning department access ===
=== Waiting for OpenCAD web interface ===
=== Configuring Firefox ===
=== Launching Firefox ===
=== OpenCAD setup complete ===
Login credentials: admin@opencad.local / Admin123!
Web URL: http://localhost/
```

### Environment Timing
- **Total setup**: ~129s (from `env.reset()` output)
- **pre_start + post_start**: ~114s
- **pre_task hooks**: ~15s

### Key Database State After Setup
- **users**: 5 (1 placeholder + admin + dispatch + 2 pending)
- **incident_types**: 78 (10-0 through 10-84)
- **streets**: Full GTAV street list (400+ entries)
- **ncic_names**: 4 (Michael De Santa, Franklin Clinton, Trevor Philips, Amanda De Santa)
- **bolos_vehicles**: 1 (Declasse Vigero)
- **bolos_persons**: 1 (armed robbery suspect)
- **ncic_citations**: 1 (Reckless Driving for Trevor)
- **call_history**: 5 (historical calls for context)

## New Task Validation Evidence (Phase 5, added 2026-03-03)

### Do-Nothing Tests
All 5 new tasks tested: `do_nothing_test_results.json`
- `fugitive_traffic_stop`: score=0, passed=False ✓
- `armed_robbery_response`: score=0, passed=False ✓
- `new_resident_full_processing`: score=0, passed=False ✓
- `major_incident_documentation`: score=0, passed=False ✓
- `multi_jurisdiction_pursuit`: score=0, passed=False ✓

### Wrong-Target & Partial Completion Tests
All 12 tests passed: `validation_test_results.json`

| Task | Test | Expected Score | Actual Score | Result |
|------|------|---------------|-------------|--------|
| fugitive_traffic_stop | wrong-target citation (Franklin→id=99) | 35 | 35 | PASS |
| fugitive_traffic_stop | partial (call only) | 35 | 35 | PASS |
| armed_robbery_response | wrong-target warrant (Trevor→id=99) | 20 | 20 | PASS |
| armed_robbery_response | partial (call + vehicle BOLO) | 45 | 45 | PASS |
| new_resident_full_processing | wrong-target civilian (John Doe) | 0 | 0 | PASS |
| new_resident_full_processing | partial (civilian only) | 25 | 25 | PASS |
| new_resident_full_processing | partial (civilian + vehicle) | 60 | 60 | PASS |
| major_incident_documentation | wrong-target citation (Michael→id=99) | 30 | 30 | PASS |
| major_incident_documentation | partial (call + BOLO, no citation) | 55 | 55 | PASS |
| multi_jurisdiction_pursuit | wrong-target warrant (Trevor→id=99) | 15 | 15 | PASS |
| multi_jurisdiction_pursuit | wrong-target citation (wrong person) | 65 | 65 | PASS |
| multi_jurisdiction_pursuit | partial (call + vehicle BOLO) | 35 | 35 | PASS |

### Per-Task Evidence Files
- `fugitive_traffic_stop_evidence.json` — scoring breakdown, test results, seed data
- `armed_robbery_response_evidence.json` — scoring breakdown, test results, seed data
- `new_resident_full_processing_evidence.json` — scoring breakdown, test results, seed data
- `major_incident_documentation_evidence.json` — scoring breakdown, test results, seed data
- `multi_jurisdiction_pursuit_evidence.json` — scoring breakdown, test results, seed data

### Screenshots
- `fugitive_traffic_stop_screenshot.png` — do-nothing state at reset
- `armed_robbery_response_screenshot.png` — do-nothing state at reset
- `new_resident_full_processing_screenshot.png` — do-nothing state at reset
- `major_incident_documentation_screenshot.png` — do-nothing state at reset
- `multi_jurisdiction_pursuit_screenshot.png` — do-nothing state at reset

---

## Phase 7.2 Verification Checklist

- [x] Installation script completes without errors
- [x] Setup script completes without errors (all 16 milestones reached)
- [x] Application is visible in screenshot (OpenCAD login page)
- [x] Application is in correct initial state (login page with version 0.3.2)
- [x] Task setup runs without errors (pre_task hook for create_dispatch_call)
- [x] Export script produces valid JSON (create_dispatch_call_export.json)
- [x] Verifier can read and process the result (via copy_from_env/SFTP)
- [x] Verification returns expected result (100/100 on clean restart)
