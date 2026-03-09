# Vtiger CRM Environment - Evidence Documentation

## Environment Overview

| Property | Value |
|----------|-------|
| Application | Vtiger CRM 8.3.0 (open source) |
| Architecture | Docker-in-QEMU (php:8.1-apache-bookworm + mariadb:10.11) |
| VM Base Image | ubuntu-gnome-systemd_highres |
| Resolution | 1920x1080 |
| URL | http://localhost:8000 |
| Admin Credentials | admin / password |

## Phase 7 Verification Checklist

### Installation script completes without errors
- **Status**: PASS
- **Log**: `env_setup_pre_start.log` (257 lines)
- **Key output** (final lines):
  ```
  Setting up scrot (1.7-1) ...
  Processing triggers for man-db (2.10.2-1) ...
  Processing triggers for libc-bin (2.35-0ubuntu3.11) ...
  Running kernel seems to be up-to-date.
  No services need to be restarted.
  ```

### Setup script completes without errors
- **Status**: PASS
- **Log**: `env_setup_post_start.log` (2273 lines)
- **Key milestones** from log:
  ```
  MariaDB is ready (0s)
  Vtiger is ready (HTTP 302) (10s)
  Config file created successfully.
  Loading Vtiger framework...
  Connecting to database...
  Initializing schema...
  Installing modules...
    Schema installation done
    Login page verified OK
    Data seeding complete
    Contacts: 20
    Organizations: 15
  Firefox window detected (3s)
  === Vtiger CRM setup complete ===
    URL: http://localhost:8000
  ```

### Application is visible and accessible
- **Status**: PASS
- **HTTP status**: 200
- **Screenshot**: `login_page.png` - Shows Vtiger CRM login page with username/password fields
- **Docker containers**: Both `vtiger-app` and `vtiger-db` running healthy

### Real data loaded and verified
- **Status**: PASS
- **Evidence**: `seed_counts.txt`
- **Data counts** (verified via direct DB queries):

  | Entity | Count |
  |--------|-------|
  | Contacts | 20 |
  | Organizations | 15 |
  | Products | 10 |
  | Deals (Potentials) | 12 |
  | Tickets (HelpDesk) | 8 |
  | Calendar Events | 5 |
  | Database Tables | 526 |

### Task start states verified via visual_grounding

All 5 task pre_task hooks tested and verified with MCP visual_grounding tool:

| Task | Target Module | Screenshot | Verified Elements |
|------|--------------|------------|-------------------|
| create_contact | Contacts list | `final_create_contact_start.png` | 15+ contacts visible with names, titles, orgs, emails, phones. "Add Contact" button at top right. |
| create_organization | Organizations list | `final_create_organization_start.png` | 15 organizations visible with billing cities, websites, phones. "Add Organization" button at top right. |
| create_deal | Opportunities list | `final_create_deal_start.png` | 12 deals visible with names and amounts ($55K-$750K). "Add Opportunity" button at top right. |
| create_ticket | Tickets list | `final_create_ticket_start.png` | 8 tickets visible with titles, status (Open/Closed/In Progress), priority. "Add Ticket" button at top right. |
| schedule_calendar_event | Calendar list | `final_schedule_calendar_event_start.png` | 5 events visible with subjects, dates, activity types. "Add Event" and "Add Task" buttons at top right. |

## Timing

| Phase | Duration |
|-------|----------|
| pre_start (installation) | ~67s |
| post_start (setup + data seeding) | ~204s |
| pre_task (login + navigate) | ~25s |
| **Total from pre_start cache** | ~229s |

## Files in This Directory

### Screenshots
- `login_page.png` - Vtiger CRM login page
- `dashboard_after_login.png` - Dashboard after successful login
- `contacts_list_after_login.png` - Contacts module list view
- `organizations_list.png` - Organizations module list view
- `deals_list.png` - Opportunities/Deals module list view
- `tickets_list.png` - Tickets/HelpDesk module list view
- `live_contacts_list.png` - Live contacts list during testing
- `live_add_contact_form.png` - Add Contact form during testing
- `final_test_post_start.png` - State immediately after post_start (final test run)
- `final_create_contact_start.png` - Task start state: Contacts list (final verified)
- `final_create_organization_start.png` - Task start state: Organizations list (final verified)
- `final_create_deal_start.png` - Task start state: Opportunities list (final verified)
- `final_create_ticket_start.png` - Task start state: Tickets list (final verified)
- `final_schedule_calendar_event_start.png` - Task start state: Calendar list (final verified)

### Logs
- `env_setup_pre_start.log` - Full output of install_vtiger.sh (257 lines)
- `env_setup_post_start.log` - Full output of setup_vtiger.sh (2273 lines)
- `seed_counts.txt` - Database record counts verified via SQL
- `task_pre_task.log` - Sample pre_task hook output

### Other Evidence
- `docker_ps.txt` - Docker container status
- `firefox_ps.txt` - Firefox process listing
- `wmctrl_windows.txt` - Window list after setup
- `xdpyinfo.txt` - X display info (resolution verification)
- `summary.json` - Machine-readable summary of all verification data

## Known Issues

1. **Post-start auto-login unreliable**: The setup_vtiger.sh auto-login via xdotool coordinates may fail if Firefox hasn't fully rendered the login page. The pre_task hooks now include `ensure_vtiger_logged_in()` which always performs a fresh login before navigating to the target module, making the post_start login failure a non-issue.

2. **Smarty template permissions**: Vtiger's Smarty template engine requires writable `test/templates_c/` directory. The setup script applies `chmod -R 777` to `test/`, `cache/`, `storage/`, and `logs/` directories after schema installation.

3. **Firefox snap warnings**: The snap-based Firefox emits harmless GTK and snapd mount warnings on launch. These do not affect functionality.
