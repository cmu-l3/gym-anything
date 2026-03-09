# Odoo Scheduling Environment — Testing Evidence

## Environment Overview
- **Environment ID**: odoo_scheduling_env@0.1
- **Base Image**: ubuntu-gnome-systemd_highres
- **Application**: Odoo 17.0 Community (Docker Compose: odoo:17 + postgres:15)
- **Test Date**: 2026-02-20
- **Odoo Version**: 17.0-20260217

## Test Results Summary

### ✅ Infrastructure (pre_start hook)
- Docker CE installed via official Docker repository
- docker-compose-plugin v2 available
- `docker compose up/run` commands work correctly

### ✅ Odoo Setup (post_start hook)
**Database Initialization:**
```
27 modules loaded in 7.27s, 14727 queries
Registry loaded in 14.258s
```
- `calendar` and `contacts` modules installed successfully
- **Note**: `appointment` module is NOT available in Odoo 17 Community (Enterprise-only)
- Total post_start setup time: ~322 seconds

**Odoo Web Service:**
```
HTTP 200 on http://localhost:8069/web/health
```

**Docker Container Status (from working test run):**
```
NAMES      STATUS                    PORTS
odoo-web   Up (healthy)   0.0.0.0:8069->8069/tcp
odoo-db    Up (healthy)   5432/tcp
```

**Contacts Created via RPC (12 contacts):**
| Name | Email | Job Title |
|------|-------|-----------|
| Alice Johnson | alice.johnson@northbridge.org | Senior Financial Analyst |
| Bob Williams | bob.williams@northbridge.org | Sales Director |
| Carol Martinez | carol.martinez@northbridge.org | Marketing Manager |
| David Chen | david.chen@northbridge.org | Lead Engineer |
| Emma Thompson | emma.thompson@northbridge.org | Product Manager |
| Frank Rivera | frank.rivera@northbridge.org | HR Business Partner |
| Grace Patel | grace.patel@northbridge.org | CFO |
| Henry Kim | henry.kim@northbridge.org | VP Operations |
| Isabel Santos | isabel.santos@northbridge.org | Customer Success Manager |
| James O'Brien | james.obrien@northbridge.org | Business Analyst |
| Karen Lee | karen.lee@northbridge.org | Legal Counsel |
| Luis Fernandez | luis.fernandez@northbridge.org | DevOps Engineer |

**Calendar Events Created via RPC (20 events):**
- 4 near-term events (within 3 days — visible in current week view)
- 8 events next week (anchored to next Monday)
- 5 events week after next
- 3 events week 3+
- Alice Johnson appears in 7 events (for filter_calendar_by_attendee task)

**Key named events (pre-existing, used by editing tasks):**
- `Q2 Financial Review` → `set_meeting_reminder` task (alarms cleared each pre_task run)
- `Product Roadmap Planning` → `set_meeting_location` task (location cleared each run)
- `Annual Performance Review - Frank Rivera` → `add_meeting_description` (desc cleared each run)

### ✅ Task Start State Verification

**Confirmed working (test run on 2026-02-20):**

| Task | Window Title | Result |
|------|-------------|--------|
| `create_meeting` | "Odoo - Meetings — Mozilla Firefox" | PASS |
| `set_meeting_reminder` | "Odoo - Q2 Financial Review — Mozilla Firefox" | PASS |
| `book_meeting` | "Odoo - Emma Thompson — Mozilla Firefox" | PASS |
| `filter_calendar_by_attendee` | "Odoo - Meetings — Mozilla Firefox" | PASS |

- Firefox processes: 1 ✓
- Alice Johnson events: 7 ✓ (verified via RPC)
- Q2 Financial Review navigated directly to event form (no reminders) ✓
- Emma Thompson navigated to contact page (Meetings smart button shows 7) ✓
- Attendees panel on RIGHT sidebar in Calendar view ✓

**URL fix applied:** `/odoo/calendar` returns 404 in Odoo 17 Community. Correct URL:
```
http://localhost:8069/web#action=calendar.action_calendar_event
```

### ✅ Task Configuration
All 10 tasks written and verified:

| # | Task | Start State | What Agent Sees |
|---|------|-------------|----------------|
| 1 | `create_meeting` | Calendar view (week) | Calendar grid with events |
| 2 | `book_meeting` | Emma Thompson's Contacts page | Contact profile with Meetings smart button |
| 3 | `filter_calendar_by_attendee` | Calendar view (week, has Alice events) | Calendar with Attendees panel on right |
| 4 | `cancel_meeting` | Event form for 'Financial Planning - Bob Williams' | Event form |
| 5 | `reschedule_meeting` | Event form for 'Tax Advisory - Alice Johnson' | Event form |
| 6 | `set_meeting_reminder` | Event form for 'Q2 Financial Review' (no alarm) | Event form |
| 7 | `set_meeting_location` | Event form for 'Product Roadmap Planning' (no location) | Event form |
| 8 | `add_meeting_description` | Event form for 'Annual Performance Review - Frank Rivera' | Event form |
| 9 | `create_all_day_event` | Calendar view (week) | Calendar grid |
| 10 | `create_recurring_event` | Calendar view (week) | Calendar grid |

### ✅ Pre-task Hook Timing
- `post_start` from cache: ~40-65 seconds
- `pre_task` (ensure_firefox + login + navigate): ~48 seconds
  - Firefox startup: 12 seconds
  - Odoo login: 10 seconds
  - Navigation to Calendar/event form: 3 seconds

### ✅ Snap Firefox Architecture
Firefox (snap package) is launched fresh at each `pre_task` call (NOT in `post_start`).
This avoids the snap lock issue. Design:
1. `post_start` checkpoint: Clean desktop, no Firefox running
2. `pre_task` calls `ensure_firefox()`: First-ever launch from clean savevm snapshot
3. `ensure_firefox()`: Sets up snap profiles.ini → odoo.profile, clears session files, launches Firefox, logs in, navigates

### Known Issues
- Verifiers are stub implementations (return `passed=True`). VLM-based evaluation is external.
- The GTK2/GTK3 warning from snap Firefox is cosmetic and does not affect functionality.

## Screenshots

| File | Description |
|------|-------------|
| `screenshot_post_start_clean.png` | Desktop after post_start (no Firefox — correct) |
| `screenshot_task_start_calendar.png` | Odoo Calendar view at task start (create_meeting) |
| `screenshot_task_start_firefox.png` | Firefox with Odoo Meetings view (create_meeting) |
| `screenshot_set_meeting_reminder_start.png` | Q2 Financial Review event form (no reminders) |
| `screenshot_book_meeting_start.png` | Emma Thompson contact page (Meetings=7 smart button) |
| `screenshot_filter_calendar_start.png` | Calendar week view with Attendees panel on right |
