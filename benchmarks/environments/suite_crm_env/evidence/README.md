# SuiteCRM Environment - Evidence Documentation

## Environment Overview

- **Application**: SuiteCRM 7.14.6 (open-source CRM)
- **Architecture**: Docker-in-QEMU (php:8.1-apache-bookworm + mariadb:10.11)
- **Base Image**: ubuntu-gnome-systemd_highres
- **Resources**: 4 CPU, 8GB RAM, networking enabled
- **Browser**: Firefox (snap), auto-configured with SuiteCRM homepage
- **Admin Credentials**: admin / Admin1234!

## Checklist Verification

### Installation (pre_start)
- [x] Docker CE and Docker Compose v2 plugin installed
- [x] Firefox, wmctrl, xdotool, scrot, jq installed
- [x] All dependencies installed without errors

**Log excerpt** (pre_start):
```
=== Installing SuiteCRM Dependencies ===
... (apt-get update + install) ...
Setting up jq (1.6-2.1ubuntu3.1) ...
=== SuiteCRM dependency installation complete ===
```

### Setup (post_start)
- [x] Docker Compose build completes (suitecrm-app + suitecrm-db)
- [x] MariaDB healthy (ready in ~0s from cache)
- [x] SuiteCRM web server responds (HTTP 200 within 20s)
- [x] Silent install completes (curl fallback after PHP CLI fails)
- [x] config.php created successfully
- [x] vendor/autoload.php present (pre-built release ZIP)
- [x] 82 records seeded via SugarBean API
- [x] Firefox configured with first-run suppression
- [x] Auto-login to SuiteCRM dashboard

**Log excerpt** (post_start):
```
=== Setting up SuiteCRM ===
--- Waiting for MariaDB ---
MariaDB is ready (0s)
--- Waiting for SuiteCRM application ---
SuiteCRM is ready (HTTP 200) (20s)
--- Running SuiteCRM silent install ---
  Running PHP CLI silent install...
  PHP CLI install failed, trying curl-based approach...
  config.php exists after curl: yes
  Silent install done
  SuiteCRM config.php exists
  Login page verified OK
--- Seeding CRM data ---
=== Data Seeding Complete ===
Accounts: 20, Contacts: 20, Opportunities: 14, Cases: 12, Meetings: 7, Calls: 8
--- Setting up Firefox ---
  Found Firefox profile at: /home/ga/snap/firefox/common/.mozilla/firefox/7flt3nyf.default
--- Launching Firefox ---
Firefox window detected (3s)
--- Logging into SuiteCRM ---
=== SuiteCRM setup complete ===
  URL: http://localhost:8000
  Admin: admin / Admin1234!
```

### Docker Container Status
```
NAMES          STATUS                   IMAGE                   PORTS
suitecrm-app   Up 3 minutes             suitecrm-suitecrm-app   0.0.0.0:8000->80/tcp
suitecrm-db    Up 3 minutes (healthy)   mariadb:10.11           3306/tcp
```

### Database Record Counts
```
accounts       20
contacts       20
opportunities  14
cases          12
meetings        7
calls           8
Total:         82
```

### File Integrity Checks
```
vendor/autoload.php: EXISTS
config.php: EXISTS
```

## Task Start State Screenshots

All task start states verified via visual_grounding MCP tool at 1920x1080 resolution.

### 1. create_account (task_create_account.png)
- **Module**: Accounts list view
- **Data visible**: 20 Fortune 500 company accounts (Apple, Microsoft, Alphabet, Amazon, etc.)
- **Sidebar**: "Create Account", "View Accounts", "Import Accounts"
- **User**: Logged in as admin
- **Columns**: Name, City, Billing Country, Phone, User, Email Address, Date Created

### 2. create_contact (task_create_contact.png)
- **Module**: Contacts list view
- **Data visible**: 20 contacts with names (Mr./Ms./Dr. prefixes), job titles, account associations
- **Sidebar**: "Create Contact", "Create Contact From vCard", "View Contacts", "Import Contacts"
- **User**: Logged in as admin
- **Columns**: Name, Job Title, Account Name, Email, Office Phone, User, Date Created

### 3. create_opportunity (task_create_opportunity.png)
- **Module**: Opportunities list view
- **Data visible**: 14 opportunities with company names, sales stages, dollar amounts ($750K-$5.8M)
- **Sidebar**: "Create Opportunity", "View Opportunities", "Import Opportunities"
- **User**: Logged in as admin
- **Columns**: Name, Account Name, Sales Stage, Amount, Close Date, User, Date Created

### 4. create_case (task_create_case.png)
- **Module**: Cases list view
- **Data visible**: 12 support cases with subjects, priorities (High/Medium/Low), statuses
- **Sidebar**: "Create Case", "View Cases", "Import Cases"
- **User**: Logged in as admin
- **Columns**: Num, Subject, Account Name, Priority, Status, Assigned to, Date Created

### 5. schedule_meeting (task_schedule_meeting.png)
- **Module**: Meetings list view
- **Data visible**: 7 meetings with subjects, contacts, start dates
- **Sidebar**: "Schedule Meeting", "View Meetings", "Import Meetings"
- **User**: Logged in as admin
- **Columns**: Close, Subject, Contact, Related to, Start Date, Assigned User, Date Created

## Data Details

### Accounts (20 Fortune 500 companies)
Apple Inc., Microsoft Corporation, Alphabet Inc., Amazon.com Inc., Meta Platforms Inc.,
NVIDIA Corporation, Tesla Inc., Salesforce Inc., JPMorgan Chase & Co., Goldman Sachs Group Inc.,
Johnson & Johnson, Boeing Company, Cisco Systems Inc., Adobe Inc., Walmart Inc.,
AT&T Inc., Accenture plc, ExxonMobil Corporation, General Electric Company, Deloitte LLP

### Contacts (20 professionals)
Each with realistic job titles (CEO, CTO, VP, Director, etc.) linked to seeded accounts.

### Opportunities (14 enterprise deals)
Ranging from $750,000 to $5,800,000 across various sales stages.

### Cases (12 support tickets)
Technical issues with priorities (High/Medium/Low) and statuses (Assigned/Closed/New).

### Meetings (7 business meetings)
Executive dinners, QBRs, technical deep dives, compliance reviews, contract negotiations.

### Calls (8 sales/support calls)
Pipeline reviews, product demos, partnership discussions.

## Key Technical Notes

- SuiteCRM 7.14.6 uses pre-built release ZIP (not source archive) to include vendor/ directory
- Silent install uses curl fallback when PHP CLI fails ("Bad data passed in")
- Login coordinates calibrated at 1920x1080: Username=(995,480), Password=(995,539), LOG IN=(995,597)
- GUI xdotool commands must run as `ga` user (not root) for reliable Firefox interaction
- All xdotool sequences run in single shell session via `run_as_ga()` helper
