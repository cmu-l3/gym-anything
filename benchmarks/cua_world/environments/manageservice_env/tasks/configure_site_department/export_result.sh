#!/bin/bash
echo "=== Exporting configure_site_department results ==="

source /workspace/scripts/task_utils.sh

# 1. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get Initial Counts
INITIAL_SITE_COUNT=$(cat /tmp/initial_site_count.txt 2>/dev/null || echo "0")
INITIAL_DEPT_COUNT=$(cat /tmp/initial_dept_count.txt 2>/dev/null || echo "0")

# 3. Identify Tables (from setup or rediscovery)
SITE_TABLE=$(cat /tmp/site_table_name.txt 2>/dev/null || echo "SiteDefinition")
DEPT_TABLE=$(cat /tmp/dept_table_name.txt 2>/dev/null || echo "DepartmentDefinition")

# 4. Check for Specific Entities (Case Insensitive)
# We use sdp_db_exec to run SQL queries inside the container

# Check Site
echo "Checking for site 'Chicago Downtown Office'..."
SITE_QUERY="SELECT count(*) FROM $SITE_TABLE WHERE LOWER(siteName) LIKE '%chicago downtown%' OR LOWER(name) LIKE '%chicago downtown%'"
SITE_FOUND_COUNT=$(sdp_db_exec "$SITE_QUERY" 2>/dev/null | tr -d '[:space:]' || echo "0")

# Check Description
echo "Checking site description..."
# Note: Column names vary, try common ones
DESC_QUERY="SELECT count(*) FROM $SITE_TABLE WHERE (LOWER(siteName) LIKE '%chicago downtown%' OR LOWER(name) LIKE '%chicago downtown%') AND (LOWER(description) LIKE '%midwest%' OR LOWER(desc) LIKE '%midwest%')"
DESC_FOUND_COUNT=$(sdp_db_exec "$DESC_QUERY" 2>/dev/null | tr -d '[:space:]' || echo "0")

# Check Departments
echo "Checking departments..."
check_dept() {
    local dname=$1
    local query="SELECT count(*) FROM $DEPT_TABLE WHERE LOWER(deptName) LIKE '%$dname%' OR LOWER(name) LIKE '%$dname%'"
    sdp_db_exec "$query" 2>/dev/null | tr -d '[:space:]' || echo "0"
}

DEPT_NET_COUNT=$(check_dept "network operations")
DEPT_DESK_COUNT=$(check_dept "desktop support")
DEPT_SEC_COUNT=$(check_dept "information security")

# 5. Get Current Total Counts (Anti-Gaming)
CURRENT_SITE_TOTAL=$(sdp_db_exec "SELECT count(*) FROM $SITE_TABLE" 2>/dev/null | tr -d '[:space:]' || echo "0")
CURRENT_DEPT_TOTAL=$(sdp_db_exec "SELECT count(*) FROM $DEPT_TABLE" 2>/dev/null | tr -d '[:space:]' || echo "0")

# 6. Check if App is Running
APP_RUNNING="false"
if pgrep -f "WrapperJVMMain" >/dev/null || pgrep -f "wrapper.java" >/dev/null; then
    APP_RUNNING="true"
fi

# 7. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "app_running": $APP_RUNNING,
    "initial_site_count": ${INITIAL_SITE_COUNT:-0},
    "initial_dept_count": ${INITIAL_DEPT_COUNT:-0},
    "current_site_total": ${CURRENT_SITE_TOTAL:-0},
    "current_dept_total": ${CURRENT_DEPT_TOTAL:-0},
    "site_found_count": ${SITE_FOUND_COUNT:-0},
    "site_desc_match_count": ${DESC_FOUND_COUNT:-0},
    "dept_network_count": ${DEPT_NET_COUNT:-0},
    "dept_desktop_count": ${DEPT_DESK_COUNT:-0},
    "dept_security_count": ${DEPT_SEC_COUNT:-0},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location (safe permission handling)
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="