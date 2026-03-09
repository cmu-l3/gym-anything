# Aerobridge Environment — Evidence Documentation

## Phase 6 Interactive Testing Summary (2026-02-20)

All 5 tasks were walked through end-to-end via SSH + VNC on a running QEMU VM
(SSH port 2243, VNC port 5903 / display :1). Tasks were completed by a human
tester using xdotool + visual_grounding MCP, simulating agent interaction.

### End-to-End Test Results

| Task | Completed | Evidence Screenshot | DB Verified | Notes |
|------|-----------|--------------------|----|-------|
| `register_aircraft` | ✓ | `evidence_register_aircraft_*.png` | ✓ | Phoenix Mk3, final_assembly status=2 |
| `add_manufacturer` | ✓ | `evidence_add_manufacturer_success.png` | ✓ | SkyTech Innovations, country=IN |
| `add_pilot` | ✓ | `evidence_add_pilot_success.png` | ✓ | Aditya Kumar, Person popup needed |
| `create_flight_plan` | ✓ | `evidence_create_flight_plan_success.png` | ✓ | Mumbai Coastal Survey, non-empty JSON |
| `create_flight_operation` | ✓ | `evidence_create_flight_operation_success.png` | ✓ | Rajasthan Corridor Inspection |

### Key Discoveries During Interactive Testing

1. **add_manufacturer**: Task description was incomplete — Company model requires 6 fields:
   `full_name`, `common_name`, `website`, `email`, `documents` (M2M), `country`.
   Description updated in task.json to list all required fields.

2. **add_pilot**: Person model was NOT registered in Django admin by default → no '+' popup button.
   Fix: Patch `registry/admin.py` to add `admin.site.register(Person)`. Added to `setup_task.sh`.
   Pilot form also requires `address` field (FK to Address model) — added to task description.

3. **create_flight_plan**: Django `JSONField(blank=False)` rejects empty dict `{}` with
   "This field cannot be blank." Must enter non-empty JSON like `{"name": "Mumbai Coastal Survey"}`.
   Task description updated to clarify this requirement.

4. **create_flight_operation**: All 5 FKs (drone, flight_plan, operator, purpose, pilot) must be
   selected. Start/End datetime fields are also required. Task completable end-to-end.

5. **Aircraft registration**: `flight_controller_id` must be alphanumeric only (no spaces/dashes).
   `status` for `final_assembly` must be integer 2 (not string 'complete'). Both fixed in
   `setup_task.sh` for register_aircraft.

### Evidence Screenshots (in this directory)

| File | Description |
|------|-------------|
| `evidence_register_aircraft_01_login.png` | Django admin login page at task start (start state for all tasks) |
| `evidence_register_aircraft_04_saved.png` | Green banner: "The aircraft 'Phoenix Mk3' was added successfully." with aircraft list |
| `evidence_register_aircraft_05_list.png` | Aircraft list showing Phoenix Mk3 |
| `evidence_add_manufacturer_start.png` | Django admin login page at task start |
| `evidence_add_manufacturer_success.png` | Green banner: "SkyTech" company added successfully |
| `evidence_add_pilot_start.png` | Django admin login page at task start |
| `evidence_add_pilot_success.png` | Green banner: "Aditya Kumar : A.J. August Photography" pilot added |
| `evidence_create_flight_plan_start.png` | Django admin login page at task start |
| `evidence_create_flight_plan_success.png` | Green banner: "The flight plan 'Mumbai Coastal Survey' was changed successfully." |
| `evidence_create_flight_operation_start.png` | Django admin login page at task start |
| `evidence_create_flight_operation_success.png` | Green banner: "Rajasthan Corridor Inspection Flight Plan A" added |

### What Was Confirmed

1. **Aerobridge server**: Running on `http://localhost:8000/`, Django admin accessible
2. **Admin credentials**: `admin` / `adminpass123` (pre-created in `setup_aerobridge.sh`)
3. **Django admin starting state**: `http://localhost:8000/admin/login/?next=/admin/` — the login
   page, because the profile has no saved session. This is correct: the task description says
   "Log in to the admin panel using username 'admin' and password 'adminpass123'."
   After login: shows AUTHENTICATION, DIGITALSKY_PROVIDER, GCS_OPERATIONS, PKI_FRAMEWORK, REGISTRY.
4. **Firefox**: Snap Firefox launches successfully using `--new-instance` flag + snap profile path +
   snap lock file removal. Profile directory MUST be created in the snap path before launching
   (`/home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile`), otherwise Firefox shows
   "Profile Missing" dialog. Fixed in `setup_aerobridge.sh`.
5. **Server startup**: Changed from `setsid` to systemd service (`aerobridge.service`) for
   reliability. `task_utils.sh` includes auto-restart logic.
6. **Model fields verified via Django shell**:
   - `Aircraft.name` — filters by name, not nick_name
   - `Company.full_name`, `Company.country` — no `Manufacturer` model exists
   - `Person.first_name`, `Person.last_name`, `Person.email`
   - `FlightPlan.name`, `.plan_file_json`, `.geo_json` (gcs_operations app)
   - `FlightOperation.name`, `.drone`, `.flight_plan`, `.operator`, `.purpose`

## Environment Info

- **Base image**: `ubuntu-gnome-systemd_highres`
- **Aerobridge version**: v1.0.1 (from git tag, pip install)
- **Django admin**: `http://localhost:8000/admin/`
- **Python venv**: `/opt/aerobridge_venv/`
- **App directory**: `/opt/aerobridge/`
- **Database**: SQLite at `/opt/aerobridge/aerobridge.sqlite3` (from `settings.py`: `BASE_DIR / 'aerobridge.sqlite3'`)
- **SSH**: port varies, user `ga` / `password123`
- **VNC**: display :1, password `password`
