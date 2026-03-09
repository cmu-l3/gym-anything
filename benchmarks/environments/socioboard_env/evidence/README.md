# Socioboard 4.0 Environment - Testing Evidence

## Overview

This document captures the interactive testing process for the Socioboard 4.0 environment
following the environment creation workflow specified in `env_creation_notes/prompt.md`.

## Environment Status: COMPLETE - All 5 Tasks Verified ✓

All 5 benchmark tasks have been interactively tested and verified working.

## Architecture Summary

- **Frontend**: Apache 2.4 + PHP 7.4 (Laravel 5.x) at `http://localhost`
- **Backend**: 4 Node.js microservices (user:3000, publish:3001, feeds:3002, notification:3003)
- **Database**: MariaDB (socioboard) + MongoDB (socioboard)
- **Admin credentials**: admin@socioboard.local / Admin2024!
- **Second user**: john.smith@socioboard.local / User2024!

## Critical Fixes Applied

### Fix 1: API_URL Double /v1/ Issue
PHP `.env` had `API_URL_FEEDs` (lowercase) but PHP helper reads `API_URL_FEEDS` (uppercase).
Laravel `env()` is case-sensitive. Both variants now added to `.env`.

### Fix 2: Sequelize isUrl Validator Rejects localhost
The `user_details` Sequelize model uses `isUrl: { args: true }` which calls
`validator.js isURL()` with `require_tld: true` by default. `http://localhost/...`
fails because "localhost" has no TLD.
Fix: Set `require_tld: false` in both the model and `validator-extras.js`.

### Fix 3: No Timezone Field in Settings
Socioboard's settings form had no timezone dropdown. Added timezone `<select>` to
`settings.blade.php`, updated `UserController.php` to pass `userDetails` to view
and include `timeZone` in the profile update call, updated Node.js `authorizedlibs.js`
to persist `time_zone` to the database with fallback values.

### Fix 4: RSS Access Requires Premium Plan
Admin was on Basic plan (`rss_feeds=0`). RSS/Content Feeds menu is gated by plan.
Fix: `UPDATE user_activations SET user_plan = 2` (Premium plan).

### Fix 5: RSS Page Missing Feed Name Field
The `rssfeeds.blade.php` form only had a URL field. Task requires entering a feed name.
Added "Feed Name" text input above the URL field.

### Fix 6: view-team Page 500 Error for New Teams
When team is created via API (not PHP form), the PHP session is not updated. The
`TeamController::viewTeam()` relies on session data to find admin details. Added
fallback logic to scan all session profiles when the team is not found in session.

### Fix 7: Node.js notNull Violations on Profile Update
`updateUserProfiles()` passed `undefined` for fields not included in the form.
Added `|| user.fieldName` fallback for all fields.

## Task Test Results

### Task 1: create_team ✓
- **Description**: Create a team named "Digital Marketing Hub"
- **Verification**: `team_informations` table in MariaDB
- **Status**: Working. Team creation via `/create-team` form works correctly.

### Task 2: update_user_profile ✓
- **Description**: Update profile with First Name: Sarah, Last Name: Connor, About Me, Phone
- **Verification**: `user_details` table in MariaDB
- **Status**: Working after fixing phone validation (nullable) and profile update fallbacks.

### Task 3: change_timezone ✓
- **Description**: Change timezone to America/New_York in Account Settings
- **Verification**: `user_details.time_zone` in MariaDB
- **URL**: `http://localhost/settings` → Account Settings tab
- **Status**: Working after adding timezone dropdown to settings form.
- **Evidence**: Database shows `time_zone = 'America/New_York'` after form submission.

### Task 4: add_rss_feed ✓
- **Description**: Add BBC Technology News RSS feed (feeds.bbci.co.uk/news/technology/rss.xml)
- **Verification**: RSS API returns articles (feeds are not stored, fetched on-demand)
- **URL**: `http://localhost/discovery/rss-feed`
- **Status**: Working after plan upgrade and API_URL_FEEDS case fix.
- **Evidence**: BBC Technology News articles loaded (AI, ChatGPT headlines visible).

### Task 5: add_team_member ✓
- **Description**: Add john.smith@socioboard.local to Content Strategy Team
- **Verification**: `join_table_users_teams` table in MariaDB
- **URL**: `http://localhost/view-team/{team_id}` → "Invite New Team Member"
- **Status**: Working after fixing view-team 500 error (adminDetails fallback).
- **Evidence**: DB shows john.smith (user_id=2) in team 5, invitation_accepted=0 (pending).

## Screenshots

### Task Start-State Screenshots (session cleared via logout before each)
All 5 tasks share an identical visual start state: the browser navigates to `http://localhost/logout`
(clearing the Laravel session), then to `http://localhost/login` (showing the sign-in form).
The login form shows "Your e-mail address" and "Your password" fields with a red Login button.
Each task also resets relevant DB state (team deletion, profile reset, timezone reset) before
the screenshot is taken, but the login form is always the agent-visible start state.

- `task1_create_team_start.png` — Socioboard `/login` sign-in form; DB has no "Digital Marketing Hub" team (deleted during setup)
- `task2_update_user_profile_start.png` — Socioboard `/login` sign-in form; admin profile reset to first_name='Admin', last_name='User', about_me=NULL
- `task3_change_timezone_start.png` — Socioboard `/login` sign-in form; admin time_zone reset to 'NA'
- `task4_add_rss_feed_start.png` — Socioboard `/login` sign-in form; Apache log baseline recorded for POST /getRss detection
- `task5_add_team_member_start.png` — Socioboard `/login` sign-in form; "Content Strategy Team" recreated fresh with no non-admin members

### Custom UI Element Verification Screenshots
- `task2_update_user_profile_settings_page.png` — Profile Settings page with default values (Admin/User), shows First Name, Last Name, Phone, Timezone, Bio fields
- `task3_change_timezone_settings_page.png` — Account Settings page showing Timezone dropdown ("-- Select Timezone --"), confirms custom patch applied correctly
- `task4_add_rss_feed_rss_page.png` — RSS Content Manager page at `/discovery/rss-feed` showing Feed Name and Feed URL input fields with "Add Feed" button, confirms custom patch applied correctly. Note: article cards below the form show results from a previous test session — these are PHP session-cached results fetched on-demand and do NOT mean the BBC Technology News feed was already added. The verifier checks the Apache log for a POST /getRss during the current task to ensure agent interaction.
- `task5_add_team_member_team_page.png` — Content Strategy Team page (`/view-team/6`) showing only Admin as member with "Invite New Team Member" button visible (clean pre-invite state)

### End-State Evidence Screenshots (from earlier testing session)
- `evidence_add_team_member.png` — view-team page after John invited (pending member visible)
- `task5_add_team_member_final.png` — Same page confirming John's invitation
- `current_state.png` — Legacy screenshot from early testing

## Audit Fixes (2026-02-22, Audit 1)

### [BLOCKER] Start-state screenshots — FIXED
All 5 tasks now have task start-state screenshots (login form after session logout).
Custom UI elements confirmed working: timezone dropdown (task3) and RSS form (task4).
Task5 team page clean state (pre-invite) also documented.

### [HIGH] add_rss_feed verifier passable without agent interaction — FIXED
Verifier now uses a two-step check:
1. Apache access log: checks for `POST /getRss` after task start baseline (set by setup_task.sh)
2. Feeds API: confirms feed URL returns articles (existing check)
Agent must actually submit the RSS Content Manager form to pass.

### [MEDIUM] update_user_profile phone not verified — FIXED
Phone scoring (10 pts) added to verifier. Score breakdown: first_name(25) + last_name(25) + about_me(40) + phone(10). Passes at score >= 60.

### [LOW] Browser session not cleared between tasks — FIXED
All 5 setup_task.sh scripts now navigate to `/logout` before opening the task page,
ensuring the agent always starts from a logged-out state and sees the login form.

## Audit Fixes (2026-02-22, Audit 2)

### [CRITICAL BLOCKER] All 5 start screenshots identical showing wrong page — FIXED
Root causes identified and fixed:
1. **Wrong URL**: scripts navigated to `http://localhost/` (marketing page, title "SocioBoard — Mozilla Firefox") instead of `http://localhost/login` (sign-in form). Fixed: all 5 setup_task.sh scripts now navigate to `http://localhost/login`.
2. **File permission block**: `/tmp/task_start.png` from the previous pre_task hook run was owned by `root` (mode 644). The `ga` user's `scrot` call silently failed, leaving the old root-owned file unchanged. Fixed at the VM level: old root-owned files removed with `sudo rm` before re-running setup scripts.

All 5 screenshots now show the Socioboard sign-in form at `http://localhost/login` (MD5: `b5ac16483486f303c84f817bace247f3`). Screenshots are visually identical across tasks because the correct start state for all tasks is the same: logged-out browser showing the login form. Each task independently resets its relevant DB state before the screenshot.

### [CRITICAL] README falsely described screenshots as "login page" when they showed marketing page — FIXED
README Screenshot section updated to accurately describe: (a) what the screenshots show (sign-in form at /login), (b) why all 5 look identical (shared correct start state), (c) what DB state each task resets.

### [HIGH] RSS page pre-loaded articles unexplained — DOCUMENTED
The `task4_add_rss_feed_rss_page.png` UI verification screenshot shows article cards from a previous test session. These are PHP session-cached results (fetched on-demand, not stored in DB). README note updated to explain this. The verifier's Apache log check ensures agent must submit the form.

### [HIGH] add_rss_feed verifier does not verify agent used correct URL — ACKNOWLEDGED LIMITATION
Socioboard does not persist RSS feed subscriptions in the database; feeds are fetched on-demand. It is not possible to programmatically determine which URL the agent entered from DB state alone. The two-step verifier (Apache log check + feed URL validation) ensures: (1) agent submitted the RSS form at least once, (2) the BBC Technology News URL is functional. The specific URL the agent typed cannot be verified without parsing Apache POST bodies (which Apache does not log by default).

## Key URLs

| URL | Purpose |
|-----|---------|
| `http://localhost/login` | Login page |
| `http://localhost/dashboard/1` | Default team dashboard |
| `http://localhost/settings` | Account Settings (Profile + Timezone) |
| `http://localhost/discovery/rss-feed` | RSS Content Manager |
| `http://localhost/create-team` | Create new team |
| `http://localhost/view-team/{id}` | View team and invite members |

## Database Queries for Verification

```sql
-- Check team exists
SELECT team_name FROM team_informations WHERE team_name = 'Digital Marketing Hub';

-- Check profile update
SELECT first_name, last_name, about_me, phone_no FROM user_details WHERE email = 'admin@socioboard.local';

-- Check timezone
SELECT time_zone FROM user_details WHERE email = 'admin@socioboard.local';

-- Check team membership
SELECT jt.invitation_accepted, ud.email
FROM join_table_users_teams jt
JOIN team_informations ti ON jt.team_id = ti.team_id
JOIN user_details ud ON jt.user_id = ud.user_id
WHERE ti.team_name = 'Content Strategy Team'
  AND ud.email = 'john.smith@socioboard.local';
```
