# DHIS2 Environment - Verification Evidence

## Test Details

- **Date**: 2026-02-14
- **Base Image**: ubuntu-gnome-systemd_highres
- **DHIS2 Version**: 2.40.11
- **Database**: Sierra Leone demo (official DHIS2 dataset)
- **Task**: register_child
- **Test**: Clean start with `use_cache=False`
- **Total Setup Time**: 204s (171s env setup + 33s task hooks)

---

## Screenshots

### 01_login_page.png
DHIS2 login page showing "DHIS 2 Demo - Sierra Leone" banner, Username/Password fields, and "Log in with admin / district" helper text. Confirms DHIS2 is running and accessible in Firefox.

### 02_dashboard.png
Post-login DHIS2 dashboard showing "Antenatal Care" dashboard with data visualizations (maps of Africa, coverage charts). Confirms successful login with admin/district credentials and that the Sierra Leone demo data is loaded.

### 03_tracker_capture.png
Tracker Capture app showing organisation unit tree (Sierra Leone root), program selector dropdown, and "search"/"register" buttons. This is the starting point for the register_child task.

---

## Verification Checklist

### Installation Script (pre_start hook)
- **Status**: PASSED
- **Log**: `env_setup_pre_start.log`
- **Output snippet**:
```
Setting up jq (1.6-2.1ubuntu3.1) ...
Processing triggers for man-db (2.10.2-1) ...
Cleaning up...
=== DHIS2 Dependencies Installation Complete ===
```

### Setup Script (post_start hook)
- **Status**: PASSED
- **Log**: `env_setup_post_start.log`
- **Output snippet**:
```
Starting DHIS2 application container...
DHIS2 is ready after 10s (HTTP 200)
Setting up Firefox profile...
Firefox window detected after 1s
=== DHIS2 Setup Complete ===
```

### Docker Containers
- **Status**: PASSED
```
NAMES       STATUS                    PORTS
dhis2-app   Up 13 minutes (healthy)   0.0.0.0:8080->8080/tcp, [::]:8080->8080/tcp
dhis2-db    Up 14 minutes (healthy)   5432/tcp
```

### DHIS2 API Response
- **Status**: PASSED
```json
{
    "contextPath": "http://localhost:8080",
    "version": "2.40.11",
    "revision": "c898871",
    "databaseInfo": {
        "spatialSupport": true
    }
}
```

### Database Statistics
- **Status**: PASSED
```
Tables: 439
Organisation Units: 1332
Tracked Entity Instances: 73124
```

### Task Prerequisites
- **Status**: PASSED

**Ngelehun CHC Organisation Unit**:
```json
{
    "name": "Ngelehun CHC",
    "id": "DiszpKrYNg8",
    "level": 4
}
```

**Child Programme**:
```json
{
    "name": "Child Programme",
    "programType": "WITH_REGISTRATION",
    "id": "IpHINAT79UW"
}
```

### Task Setup Script (pre_task hook)
- **Status**: PASSED
- Records initial tracked entity count: 73124
- Verifies DHIS2 health check passes
- Ensures Firefox is running and focused

### Export Script (post_task hook)
- **Status**: PASSED
- All SQL queries execute without errors against `trackedentityinstance` table
- API call to `trackedEntityInstances.json` succeeds with program parameter
- JSON result file generated correctly at `/tmp/register_child_result.json`
- **Output** (before any child registration):
```json
{
    "initial_tracked_entity_count": 73124,
    "current_tracked_entity_count": 73124,
    "entity_found": false,
    "entity": {
        "uid": "",
        "first_name": "",
        "last_name": "",
        "dob": "",
        "sex": ""
    },
    "export_timestamp": "2026-02-14T08:22:53+00:00"
}
```

### Application Visible in Screenshot
- **Status**: PASSED
- See 01_login_page.png (login page), 02_dashboard.png (post-login dashboard), 03_tracker_capture.png (Tracker Capture app)

### Application in Correct Initial State
- **Status**: PASSED
- Sierra Leone demo database loaded with 73,124 tracked entity instances
- Firefox opens to DHIS2 login page
- Login with admin/district works
- Tracker Capture app accessible with org unit tree and program selector

---

## Key Configuration

| Parameter | Value |
|-----------|-------|
| CPU | 4 |
| RAM | 8GB |
| DHIS2 Image | dhis2/core:2.40.11 |
| PostgreSQL Image | postgis/postgis:14-3.4-alpine |
| DHIS2 URL | http://localhost:8080 |
| Credentials | admin / district |
| Ngelehun CHC ID | DiszpKrYNg8 |
| Child Programme ID | IpHINAT79UW |
