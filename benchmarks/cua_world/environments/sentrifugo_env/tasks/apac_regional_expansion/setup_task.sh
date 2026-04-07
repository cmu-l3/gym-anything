#!/bin/bash
echo "=== Setting up apac_regional_expansion task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60
date +%s > /tmp/task_start_timestamp

log "Cleaning up prior run artifacts..."

# ---- 1. Clean up time module (children first) ----
# Time module uses tm_ prefixed tables, not main_
PROJ_ID=$(sentrifugo_db_query "SELECT id FROM tm_projects WHERE project_name='Singapore Office Launch' LIMIT 1;" | tr -d '[:space:]')
if [ -n "$PROJ_ID" ]; then
    sentrifugo_db_root_query "DELETE FROM tm_project_employees WHERE project_id=${PROJ_ID};" 2>/dev/null || true
    sentrifugo_db_root_query "DELETE FROM tm_project_task_employees WHERE project_id=${PROJ_ID};" 2>/dev/null || true
    sentrifugo_db_root_query "DELETE FROM tm_project_tasks WHERE project_id=${PROJ_ID};" 2>/dev/null || true
    sentrifugo_db_root_query "DELETE FROM tm_projects WHERE id=${PROJ_ID};" 2>/dev/null || true
fi
sentrifugo_db_root_query "DELETE FROM tm_clients WHERE client_name='APAC Regional Program';" 2>/dev/null || true
# Also clean up any tasks created in tm_tasks
sentrifugo_db_root_query "DELETE FROM tm_tasks WHERE task IN ('Office Infrastructure Setup','Client Onboarding Pipeline');" 2>/dev/null || true

# ---- 2. Clean up employees (children before parent tables) ----
for EMPID in EMP025 EMP026 EMP027 025 026 027; do
    UID_VAL=$(sentrifugo_db_query "SELECT id FROM main_users WHERE employeeId='${EMPID}' LIMIT 1;" | tr -d '[:space:]')
    if [ -n "$UID_VAL" ]; then
        sentrifugo_db_root_query "DELETE FROM tm_project_employees WHERE emp_id=${UID_VAL};" 2>/dev/null || true
        sentrifugo_db_root_query "DELETE FROM main_managers WHERE user_id=${UID_VAL};" 2>/dev/null || true
        sentrifugo_db_root_query "DELETE FROM main_employees_summary WHERE user_id=${UID_VAL};" 2>/dev/null || true
        sentrifugo_db_root_query "DELETE FROM main_employees WHERE user_id=${UID_VAL};" 2>/dev/null || true
        sentrifugo_db_root_query "DELETE FROM main_users WHERE id=${UID_VAL};" 2>/dev/null || true
    fi
done

# ---- 3. Clean up holiday group and dates ----
HG_ID=$(sentrifugo_db_query "SELECT id FROM main_holidaygroups WHERE groupname='Singapore Office Holidays 2026' LIMIT 1;" | tr -d '[:space:]')
if [ -n "$HG_ID" ]; then
    sentrifugo_db_root_query "DELETE FROM main_holidaydates WHERE groupid=${HG_ID};" 2>/dev/null || true
    sentrifugo_db_root_query "DELETE FROM main_holidaygroups WHERE id=${HG_ID};" 2>/dev/null || true
fi

# ---- 4. Clean up leave type ----
sentrifugo_db_root_query "DELETE FROM main_employeeleavetypes WHERE leavetype='Childcare Leave';" 2>/dev/null || true

# ---- 5. Clean up job titles ----
sentrifugo_db_root_query "DELETE FROM main_jobtitles WHERE jobtitlename='Regional Engineering Director';" 2>/dev/null || true
sentrifugo_db_root_query "DELETE FROM main_jobtitles WHERE jobtitlename='Client Solutions Architect';" 2>/dev/null || true

# ---- 6. Clean up departments ----
sentrifugo_db_root_query "DELETE FROM main_departments WHERE deptname='APAC Product Engineering';" 2>/dev/null || true
sentrifugo_db_root_query "DELETE FROM main_departments WHERE deptname='APAC Client Solutions';" 2>/dev/null || true

# ---- 7. Clean up business unit ----
sentrifugo_db_root_query "DELETE FROM main_businessunits WHERE unitname='Asia-Pacific Operations';" 2>/dev/null || true

# ---- 8. Clean up announcement ----
sentrifugo_db_root_query "DELETE FROM main_announcements WHERE title LIKE '%APAC Regional Expansion%';" 2>/dev/null || true

log "Cleanup complete"

# ---- Drop expansion playbook on Desktop ----
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/apac_expansion_playbook.txt << 'PLAYBOOK'
ACME GLOBAL TECHNOLOGIES
Regional Expansion Playbook — APAC Hub (Singapore)
Prepared by: Chief Operating Officer
Effective Date: March 1, 2026
Classification: Internal — HR Action Required
================================================================

EXECUTIVE SUMMARY
Acme Global Technologies is establishing an Asia-Pacific regional
headquarters in Singapore to serve our growing client base across
APAC markets. This playbook specifies all HRMS configuration
changes required before the March 17, 2026 go-live date.

================================================================
SECTION 1: ORGANIZATIONAL STRUCTURE
================================================================

1.1 Business Unit
Create a new business unit:
  Name:        Asia-Pacific Operations
  Code:        APAC
  Start Date:  2026-03-01
  Status:      Active

1.2 Departments
Create TWO departments under the Asia-Pacific Operations business unit:

  Department 1:
    Name:          APAC Product Engineering
    Code:          APAC-PE
    Business Unit: Asia-Pacific Operations

  Department 2:
    Name:          APAC Client Solutions
    Code:          APAC-CS
    Business Unit: Asia-Pacific Operations

================================================================
SECTION 2: JOB TITLES
================================================================

Create the following regional leadership positions:

  Title 1: Regional Engineering Director
    Job Code: RED-SG-01

  Title 2: Client Solutions Architect
    Job Code: CSA-SG-01

================================================================
SECTION 3: EMPLOYEE ONBOARDING
================================================================

The following three employees have accepted offers and must be
registered with ALL details specified. First day: March 17, 2026.

EMPLOYEE A:
  Employee ID:        025
  Prefix:             Mr.
  First Name:         Wei
  Last Name:          Chen
  Email:              wei.chen@acmeglobe.com
  Date of Joining:    2026-03-17
  Department:         APAC Product Engineering
  Job Title:          Regional Engineering Director
  Employment Status:  Full-Time
  Reporting Manager:  James Anderson (EMP001)

EMPLOYEE B:
  Employee ID:        026
  Prefix:             Ms.
  First Name:         Priya
  Last Name:          Sharma
  Email:              priya.sharma@acmeglobe.com
  Date of Joining:    2026-03-17
  Department:         APAC Client Solutions
  Job Title:          Client Solutions Architect
  Employment Status:  Full-Time
  Reporting Manager:  James Anderson (EMP001)

EMPLOYEE C:
  Employee ID:        027
  Prefix:             Mr.
  First Name:         Kenji
  Last Name:          Tanaka
  Email:              kenji.tanaka@acmeglobe.com
  Date of Joining:    2026-03-17
  Department:         APAC Product Engineering
  Job Title:          Software Engineer
  Employment Status:  Full-Time
  Reporting Manager:  James Anderson (EMP001)

================================================================
SECTION 4: LEAVE POLICY
================================================================

Singapore mandates childcare leave for working parents. Create:

  Leave Type:   Childcare Leave
  Leave Code:   CCL
  Days:         6
  Preallocated: Yes

================================================================
SECTION 5: HOLIDAY CALENDAR
================================================================

Create a holiday group and add the following Singapore public
holidays for 2026:

  Group Name: Singapore Office Holidays 2026

  1. New Year's Day              — 2026-01-01
  2. Chinese New Year (Day 1)    — 2026-02-17
  3. National Day                — 2026-08-09

================================================================
SECTION 6: PROJECT TIME TRACKING
================================================================

Configure the Time module for the office launch initiative:

  Client:
    Name:   APAC Regional Program
    Status: Active

  Project:
    Name:   Singapore Office Launch
    Client: APAC Regional Program
    Status: Active

  Tasks (under the project):
    a. Office Infrastructure Setup
    b. Client Onboarding Pipeline

  Resource Allocation:
    Assign Wei Chen (EMP025) and Priya Sharma (EMP026) to the
    Singapore Office Launch project.

================================================================
SECTION 7: COMPANY ANNOUNCEMENT
================================================================

Publish the following announcement:

  Title: APAC Regional Expansion — Singapore Office Opening

  Body:
  We are pleased to announce the opening of our Asia-Pacific
  regional headquarters in Singapore, effective March 17, 2026.
  The new office will house our APAC Product Engineering and
  APAC Client Solutions teams. Please join us in welcoming
  our Singapore colleagues.

================================================================
END OF PLAYBOOK
PLAYBOOK

chown ga:ga /home/ga/Desktop/apac_expansion_playbook.txt
log "Expansion playbook created at ~/Desktop/apac_expansion_playbook.txt"

# ---- Navigate to Welcome/Dashboard ----
# Use /index.php/welcome instead of /dashboard to avoid 503 on the dashboard controller
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/index.php/welcome"
sleep 3

# Maximize the window for better agent visibility
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    maximize_active_window
    sleep 1
fi

take_screenshot /tmp/task_start_screenshot.png

log "Task ready: expansion playbook on Desktop, Sentrifugo modules clean."
echo "=== Setup complete ==="
