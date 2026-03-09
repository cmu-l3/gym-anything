#!/bin/bash
# Setup script for Create Requester task
set -e

echo "=== Setting up Create Requester Task ==="

# Source SDP utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure SDP is running
echo "Waiting for ServiceDesk Plus..."
ensure_sdp_running

# 2. Prepare Database State
# We need to ensure the 'Human Resources' department exists
# and that 'Margaret Chen' does NOT exist.

echo "Configuring initial database state..."

# Check/Create Department
DEPT_CHECK=$(sdp_db_exec "SELECT DEPTNAME FROM DepartmentDefinition WHERE DEPTNAME = 'Human Resources';")
if [ -z "$DEPT_CHECK" ]; then
    echo "Creating Human Resources department..."
    # Basic insert - normally requires Site association, simplified for standard default site
    # Getting default site ID (usually 1 or derived from SiteDefinition)
    SITE_ID=$(sdp_db_exec "SELECT SITEID FROM SiteDefinition WHERE ISDELETED='false' LIMIT 1;")
    if [ -z "$SITE_ID" ]; then SITE_ID=1; fi
    
    # Insert Department
    sdp_db_exec "INSERT INTO DepartmentDefinition (DEPTID, DEPTNAME, SITEID, ISDELETED) VALUES ((SELECT COALESCE(MAX(DEPTID),0)+1 FROM DepartmentDefinition), 'Human Resources', $SITE_ID, 'false');"
else
    echo "Department 'Human Resources' already exists."
fi

# Remove Target Requester if exists (Clean Slate)
# Deleting from AaaUser usually cascades or we leave it 'deleted' status. 
# For robustness, we try to mark as deleted or hard delete.
TARGET_EMAIL="margaret.chen@pinnacletech.com"
USER_ID=$(sdp_db_exec "SELECT au.USER_ID FROM AaaUser au LEFT JOIN AaaUserContactInfo auci ON au.USER_ID=auci.USER_ID LEFT JOIN AaaContactInfo aci ON auci.CONTACTINFO_ID=aci.CONTACTINFO_ID WHERE aci.EMAILID = '$TARGET_EMAIL';")

if [ -n "$USER_ID" ]; then
    echo "Cleaning up existing user with email $TARGET_EMAIL (ID: $USER_ID)..."
    # Hard delete for clean task environment (risky in prod, okay for task container)
    # Order matters due to FKs
    sdp_db_exec "DELETE FROM RequesterDetails WHERE USERID = $USER_ID;"
    sdp_db_exec "DELETE FROM SDUser WHERE USERID = $USER_ID;"
    sdp_db_exec "DELETE FROM AaaUserContactInfo WHERE USER_ID = $USER_ID;"
    sdp_db_exec "DELETE FROM AaaUser WHERE USER_ID = $USER_ID;"
    # Note: AaaContactInfo and AaaLogin might remain orphan, which is acceptable for this task scope
fi

# Record initial count of requesters for "Do Nothing" check
INITIAL_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM SDUser sdu JOIN AaaUser au ON sdu.USERID=au.USER_ID WHERE sdu.STATUS='ACTIVE';")
echo "$INITIAL_COUNT" > /tmp/initial_requester_count.txt

# 3. Launch Application
echo "Launching Firefox..."
# Start firefox at the login page
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"

# 4. Final Setup
# Maximize window
WID=$(xdotool search --sync --onlyvisible --class "Firefox" | head -1)
if [ -n "$WID" ]; then
    xdotool windowactivate "$WID"
    wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# Take initial screenshot
sleep 2
scrot /tmp/task_initial.png

echo "=== Setup Complete ==="