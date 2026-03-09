# Matomo Environment - Evidence Documentation

## Environment Overview
- **Environment ID**: matomo_env@0.1
- **Application**: Matomo Web Analytics Platform (v5.7.0)
- **Base Image**: ubuntu-gnome-systemd_highres
- **Architecture**: Docker-in-QEMU (Matomo + MariaDB containers)

## CRITICAL: Actual Initial State

**The actual initial state is the Matomo Installation Wizard, NOT the login page.**

See screenshot: `00_actual_initial_state_installation_wizard.png`

This screenshot shows:
- Firefox browser at http://localhost
- Matomo Installation Wizard at Step 1 "Welcome"
- All 8 installation steps listed in the sidebar
- "INSTALLATION STATUS 0%" indicator

### Why This Matters
Agents starting any task in this environment will encounter the Installation Wizard first. They must complete all 8 steps before they can perform the actual task (add website, configure goal, etc.).

## Screenshots

| File | Description |
|------|-------------|
| `00_actual_initial_state_installation_wizard.png` | **ACTUAL INITIAL STATE** - Matomo Installation Wizard at Step 1 |
| `01_matomo_login_page.png` | Login page (state AFTER installation is complete) |
| `02_task_completed.png` | Task completion showing "TechBlog Demo" website created |

## Installation Wizard Steps

When an agent starts a fresh environment, they must complete these 8 steps:

1. **Welcome** - Introduction page (click "NEXT")
2. **System Check** - Verifies PHP and server requirements (automatic)
3. **Database Setup** - Enter database credentials:
   - Database Server: `db`
   - Login: `matomo`
   - Password: `matomo123`
   - Database Name: `matomo`
4. **Creating Tables** - Database schema installation (automatic)
5. **Superuser** - Create admin account:
   - Username: `admin`
   - Password: `Admin12345`
   - Email: `admin@localhost.test`
6. **Set up a Website** - Add initial tracking site (any name/URL works)
7. **JavaScript Tracking Code** - Shows tracking snippet (click "NEXT")
8. **Congratulations** - Installation complete (click "CONTINUE TO MATOMO")

## Credentials Summary

### Matomo Admin (create during Step 5)
- **Username**: admin
- **Password**: Admin12345
- **Email**: admin@localhost.test

### Database (enter during Step 3)
- **Host**: db
- **Database**: matomo
- **Username**: matomo
- **Password**: matomo123

## Task Details

### Task: add_website

**Initial State**: Installation Wizard (or login page if wizard completed)

**Task Requirements**:
- Website Name: TechBlog Demo
- Website URL: https://techblog-demo.example.com
- Timezone: Europe/London (select from Europe section)
- Currency: USD

**Verification**: Database-based with anti-gaming (checks site was created during task)

### Task: configure_goal

**Initial State**: Installation Wizard (or login page if wizard completed)

**Task Requirements**:
- Goal Name: Newsletter Signup
- Goal Type: Visit a given URL (destination)
- Pattern Type: Contains
- URL Pattern: /newsletter/thank-you
- Revenue: 5.00 USD per conversion

**Verification**: Database-based with ID-tracking anti-gaming

### Task: view_visitors_dashboard

**Initial State**: Installation Wizard (or login page if wizard completed)

**Task Requirements**:
- Navigate to Visitors > Overview
- Set date range to "Last 30 days"

**Verification**: URL and window title analysis

## Known Issues

### 1. Installation Wizard on Fresh Start (Expected Behavior)
Fresh environments always show the Installation Wizard. This is by design - Matomo requires initial configuration. Task descriptions include wizard credentials.

### 2. Docker Hub Rate Limiting
Fresh VMs may hit Docker Hub pull rate limits:
```
toomanyrequests: You have reached your unauthenticated pull rate limit.
```
**Workaround**: Wait and retry, or use authenticated Docker Hub access.

### 3. Checkpoint Restore Issues
Docker containers may not auto-restart after VM checkpoint restore.
**Workaround**:
```bash
cd /home/ga/matomo && docker-compose up -d
```

### 4. Timezone Selection
The Matomo timezone dropdown organizes by region. "UTC" is not directly selectable.
**Solution**: Use "Europe/London" which is accepted as UTC-equivalent.

## Task Timeouts

Tasks have extended timeouts to account for Installation Wizard completion:

| Task | Timeout | Max Steps |
|------|---------|-----------|
| add_website | 300s | 50 |
| configure_goal | 360s | 60 |
| view_visitors_dashboard | 300s | 45 |

## File Structure

```
benchmarks/environments/matomo_env/
├── env.json                    # Environment specification
├── config/
│   └── docker-compose.yml      # Matomo + MariaDB services
├── scripts/
│   ├── install_matomo.sh       # Pre-start hook (Docker setup)
│   ├── setup_matomo.sh         # Post-start hook (Firefox, auto-install attempt)
│   └── task_utils.sh           # Shared database utilities
├── tasks/
│   ├── add_website/
│   ├── configure_goal/
│   └── view_visitors_dashboard/
└── evidence/
    ├── README.md               # This file
    ├── 00_actual_initial_state_installation_wizard.png
    ├── 01_matomo_login_page.png
    └── 02_task_completed.png
```

## Verification Evidence

### add_website Task Completion
Screenshot `02_task_completed.png` shows successful completion:
- "TechBlog Demo" website with ID 2
- URL: https://techblog-demo.example.com
- Timezone: Europe/London
- Currency: US Dollar ($)

This proves the task CAN be completed successfully when the agent:
1. Completes the Installation Wizard
2. Logs in as admin
3. Navigates to Administration > Websites > Manage
4. Adds the website with specified details
