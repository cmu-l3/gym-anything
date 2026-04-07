#!/bin/bash
# Pre-task setup for project_timesheet_portfolio.
# - Removes any existing data for the two target clients/projects
# - Clears timesheets for the two target employees for the target week
# - Creates the project portfolio brief on the Desktop

set -euo pipefail
echo "=== Setting up project_timesheet_portfolio task ==="

source /workspace/scripts/task_utils.sh

wait_for_http "$ORANGEHRM_URL" 60

# -------------------------------------------------------
# 1. Clean up prior run artifacts
# -------------------------------------------------------
rm -f /tmp/project_timesheet_portfolio_result.json 2>/dev/null || true

# -------------------------------------------------------
# 2. Remove existing clients/projects if present
# -------------------------------------------------------
log "Cleaning up existing project data..."

for CUST_NAME in "Riverside Community Foundation" "Metro School District"; do
    CUST_ID=$(orangehrm_db_query "SELECT customer_id FROM ohrm_customer WHERE name='${CUST_NAME}' LIMIT 1;" | tr -d '[:space:]')
    if [ -n "$CUST_ID" ]; then
        # Get project IDs
        PROJ_IDS=$(orangehrm_db_query "SELECT project_id FROM ohrm_project WHERE customer_id=${CUST_ID};" 2>/dev/null | tr -d '[:space:]')
        for PID in $PROJ_IDS; do
            if [ -n "$PID" ]; then
                # Remove timesheet items for this project
                orangehrm_db_query "DELETE FROM ohrm_timesheet_item WHERE project_id=${PID};" 2>/dev/null || true
                orangehrm_db_query "DELETE FROM ohrm_project_activity WHERE project_id=${PID};" 2>/dev/null || true
                orangehrm_db_query "DELETE FROM ohrm_project WHERE project_id=${PID};" 2>/dev/null || true
            fi
        done
        orangehrm_db_query "DELETE FROM ohrm_customer WHERE customer_id=${CUST_ID};" 2>/dev/null || true
        log "Removed customer '${CUST_NAME}' (id=$CUST_ID) and its projects"
    fi
done

# -------------------------------------------------------
# 3. Resolve emp_numbers for target employees
# -------------------------------------------------------
EMP5=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE employee_id='EMP005' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
EMP15=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE employee_id='EMP015' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')

if [ -z "$EMP5" ]; then
    EMP5=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='Michael' AND emp_lastname='Thompson' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
fi
if [ -z "$EMP15" ]; then
    EMP15=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='Kevin' AND emp_lastname='Hernandez' AND purged_at IS NULL LIMIT 1;" | tr -d '[:space:]')
fi

log "EMP005 Michael Thompson: $EMP5"
log "EMP015 Kevin Hernandez: $EMP15"

# -------------------------------------------------------
# 4. Clear timesheets for target employees for week of April 7-11, 2025
# -------------------------------------------------------
for EMPNUM in "$EMP5" "$EMP15"; do
    if [ -n "$EMPNUM" ]; then
        TS_IDS=$(orangehrm_db_query "
            SELECT timesheet_id FROM ohrm_timesheet
            WHERE employee_id=${EMPNUM}
            AND ((start_date <= '2025-04-11' AND end_date >= '2025-04-07'))
        " 2>/dev/null | tr -d '[:space:]')
        for TSID in $TS_IDS; do
            if [ -n "$TSID" ]; then
                orangehrm_db_query "DELETE FROM ohrm_timesheet_item WHERE timesheet_id=${TSID};" 2>/dev/null || true
                orangehrm_db_query "DELETE FROM ohrm_timesheet WHERE timesheet_id=${TSID};" 2>/dev/null || true
            fi
        done
        log "Cleared April 7-11 timesheets for emp_number=$EMPNUM"
    fi
done

# -------------------------------------------------------
# 5. Ensure employees have OrangeHRM user accounts (needed for timesheet submission)
# -------------------------------------------------------
ESS_ROLE=$(orangehrm_db_query "SELECT id FROM ohrm_user_role WHERE name='ESS' LIMIT 1;" | tr -d '[:space:]')
ESS_ROLE="${ESS_ROLE:-2}"

for EMPNUM in "$EMP5" "$EMP15"; do
    if [ -n "$EMPNUM" ]; then
        USR_EXISTS=$(orangehrm_db_query "SELECT COUNT(*) FROM ohrm_user WHERE emp_number=${EMPNUM} AND deleted_at IS NULL;" | tr -d '[:space:]')
        if [ "${USR_EXISTS:-0}" -eq "0" ]; then
            FNAME=$(orangehrm_db_query "SELECT emp_firstname FROM hs_hr_employee WHERE emp_number=${EMPNUM} LIMIT 1;" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
            UNAME="${FNAME}${EMPNUM}"
            # Create minimal user account
            orangehrm_db_query "
                INSERT INTO ohrm_user (user_name, emp_number, user_role_id, status)
                VALUES ('${UNAME}', ${EMPNUM}, ${ESS_ROLE}, 1);
            " 2>/dev/null || true
            log "Created ESS user account for emp_number=$EMPNUM"
        fi
    fi
done

# -------------------------------------------------------
# 6. Record baseline IDs
# -------------------------------------------------------
date +%s > /tmp/task_start_timestamp
MAX_CUST_ID=$(orangehrm_db_query "SELECT COALESCE(MAX(customer_id),0) FROM ohrm_customer;" | tr -d '[:space:]')
MAX_PROJ_ID=$(orangehrm_db_query "SELECT COALESCE(MAX(project_id),0) FROM ohrm_project;" | tr -d '[:space:]')
echo "${MAX_CUST_ID:-0}" > /tmp/initial_max_cust_id.txt
echo "${MAX_PROJ_ID:-0}" > /tmp/initial_max_proj_id.txt
log "Baseline: max_cust_id=$MAX_CUST_ID, max_proj_id=$MAX_PROJ_ID"

# -------------------------------------------------------
# 7. Create the project portfolio brief on the Desktop
# -------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/q2_project_portfolio_brief.txt" << 'BRIEF'
HOPEWELL COMMUNITY SERVICES — Q2 2025 PROJECT PORTFOLIO BRIEF
==============================================================
To:    Operations Manager
From:  Executive Director
Date:  2025-04-01
Re:    Q2 Project Setup and Timesheet Submission

Please configure the following client projects in OrangeHRM and submit
staff timesheets for the week of April 7-11, 2025.

----------------------------------------------------------------------
STEP 1: CREATE CLIENTS (Admin > Projects > Customers)
----------------------------------------------------------------------
  Client 1: Riverside Community Foundation
  Client 2: Metro School District

----------------------------------------------------------------------
STEP 2: CREATE PROJECTS (Admin > Projects)
----------------------------------------------------------------------
  Project: After-School Program Expansion
  Client:  Riverside Community Foundation

  Project: Digital Literacy Initiative
  Client:  Metro School District

----------------------------------------------------------------------
STEP 3: CREATE PROJECT ACTIVITIES
----------------------------------------------------------------------
  For "After-School Program Expansion":
    Activity 1: Program Planning
    Activity 2: Community Outreach

  For "Digital Literacy Initiative":
    Activity 1: Curriculum Development
    Activity 2: Instructor Training

----------------------------------------------------------------------
STEP 4: SUBMIT TIMESHEETS (Time > My Timesheets or Timesheets > All)
  Week: April 7-11, 2025 (Monday to Friday)
----------------------------------------------------------------------
  Employee: Michael Thompson (EMP005)
    Monday Apr 7:    4h — After-School Program Expansion > Program Planning
    Tuesday Apr 8:   4h — After-School Program Expansion > Community Outreach
    Wednesday Apr 9: 8h — After-School Program Expansion > Program Planning

  Employee: Kevin Hernandez (EMP015)
    Monday Apr 7:    8h — Digital Literacy Initiative > Curriculum Development
    Tuesday Apr 8:   4h — Digital Literacy Initiative > Instructor Training
    Thursday Apr 10: 4h — Digital Literacy Initiative > Curriculum Development

  NOTE: Submit (save) the timesheets after entering hours.
----------------------------------------------------------------------
BRIEF

chown ga:ga "$DESKTOP_DIR/q2_project_portfolio_brief.txt" 2>/dev/null || true
chmod 644 "$DESKTOP_DIR/q2_project_portfolio_brief.txt"
log "Created project portfolio brief at $DESKTOP_DIR/q2_project_portfolio_brief.txt"

# -------------------------------------------------------
# 8. Navigate to Admin > Projects
# -------------------------------------------------------
TARGET_URL="${ORANGEHRM_URL}/web/index.php/admin/listProjects"
ensure_orangehrm_logged_in "$TARGET_URL"

sleep 2
take_screenshot /tmp/task_start_state.png

echo "=== project_timesheet_portfolio task setup complete ==="
echo "Employees: EMP005=$EMP5, EMP015=$EMP15"
echo "Target week: April 7-11, 2025"
