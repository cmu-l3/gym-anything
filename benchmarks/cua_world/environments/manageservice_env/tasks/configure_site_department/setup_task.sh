#!/bin/bash
set -e
echo "=== Setting up configure_site_department task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure SDP is running
# This utility waits for install (if needed) and starts the service
ensure_sdp_running

# 2. Clear mandatory password change to ensure smooth login
clear_mandatory_password_change

# 3. Record Initial State (Anti-Gaming)
echo "Recording initial database state..."

# Helper to count rows in potential tables
get_count() {
    local query="SELECT count(*) FROM $1"
    sdp_db_exec "$query" 2>/dev/null | tr -d '[:space:]' || echo "0"
}

# Try common table names for Sites and Departments across SDP versions
SITE_COUNT=0
for table in "SiteDefinition" "SiteDetails" "SDPSite" "Site"; do
    count=$(get_count "$table")
    if [ "$count" != "0" ] && [ "$count" != "" ]; then
        SITE_COUNT=$count
        echo "Found site table: $table (Count: $count)"
        echo "$table" > /tmp/site_table_name.txt
        break
    fi
done

DEPT_COUNT=0
for table in "DepartmentDefinition" "DepartmentDetails" "SDPDepartment" "Department"; do
    count=$(get_count "$table")
    if [ "$count" != "0" ] && [ "$count" != "" ]; then
        DEPT_COUNT=$count
        echo "Found department table: $table (Count: $count)"
        echo "$table" > /tmp/dept_table_name.txt
        break
    fi
done

echo "$SITE_COUNT" > /tmp/initial_site_count.txt
echo "$DEPT_COUNT" > /tmp/initial_dept_count.txt

# 4. Launch Firefox to Admin/Home
# We launch to the login page; the agent must log in and navigate to Admin
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"
sleep 5

# 5. Capture Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="