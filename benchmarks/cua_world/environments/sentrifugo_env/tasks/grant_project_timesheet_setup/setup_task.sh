#!/bin/bash
echo "=== Setting up grant_project_timesheet_setup task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60
date +%s > /tmp/task_start_timestamp

# Clean up prior run artifacts to ensure idempotency
docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -e "
DELETE FROM main_projectresources WHERE project_id IN (SELECT id FROM main_projects WHERE projectname IN ('Youth Mental Health Initiative', 'Substance Abuse Recovery', 'Housing First Program'));
DELETE FROM main_projects WHERE projectname IN ('Youth Mental Health Initiative', 'Substance Abuse Recovery', 'Housing First Program');
DELETE FROM main_clients WHERE clientname IN ('Dept of Health and Human Services', 'Oak Foundation');
" 2>/dev/null || true

# Make sure the target employees are active in the system
docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -e "
UPDATE main_users SET isactive=1 WHERE employeeId IN ('EMP006', 'EMP012', 'EMP013', 'EMP018');
" 2>/dev/null || true

# Drop the grant awards memo on the Desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/grant_awards_2026.txt << 'MEMO'
======================================================
GRANT AWARD IMPLEMENTATION MEMO - FY2026
======================================================
To: HR & Operations Manager
From: Director of Grants & Funding

We have successfully secured funding from two new grantors.
Please configure the Time Management system immediately so
our staff can begin tracking their billable hours to these
grants for our compliance reporting.

FUNDING BODY (CLIENT) 1: Dept of Health and Human Services
- Project A: Youth Mental Health Initiative
  Assigned Staff:
  * Jessica Liu (EMP006)
  * Jennifer Martinez (EMP012)
- Project B: Substance Abuse Recovery
  Assigned Staff:
  * Daniel Wilson (EMP013)

FUNDING BODY (CLIENT) 2: Oak Foundation
- Project A: Housing First Program
  Assigned Staff:
  * Nicole Anderson (EMP018)

NOTES:
- All clients and projects must be set to Active.
- Ensure exact naming for compliance audits.
======================================================
MEMO

chown ga:ga /home/ga/Desktop/grant_awards_2026.txt

# Navigate to the Sentrifugo Dashboard
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/dashboard"
sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== grant_project_timesheet_setup task setup complete ==="