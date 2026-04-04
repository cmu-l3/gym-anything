#!/bin/bash
# Export script for System Health Integrity Audit task

echo "=== Exporting System Health Integrity Audit Result ==="

source /workspace/scripts/task_utils.sh

# Helper functions
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# 1. Capture final state visual
take_screenshot /tmp/task_end_screenshot.png

# 2. Read Time anchors
TASK_START_EPOCH=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "1970-01-01T00:00:00.000Z")

# 3. Check for Report File
REPORT_PATH="/home/ga/Desktop/system_health_report.txt"
REPORT_EXISTS="false"
REPORT_CREATED_DURING="false"
REPORT_CONTENT=""
REPORT_SIZE=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -ge "$TASK_START_EPOCH" ]; then
        REPORT_CREATED_DURING="true"
    fi
    
    # Read first 2KB of content for verification
    REPORT_CONTENT=$(head -c 2048 "$REPORT_PATH" | base64 -w 0)
fi

# 4. Check API for System Tasks (Analytics & Integrity)
# We check /api/system/tasks/{type} and look for entries created >= TASK_START
# Note: In some DHIS2 versions, data integrity might not show in system/tasks, 
# but Analytics/Resource tables usually do.
# We also verify current data integrity summary to see if it was run recently.

echo "Querying system tasks..."

SYSTEM_TASKS_JSON=$(python3 <<EOF
import json, sys, requests, time
from datetime import datetime

base_url = "http://localhost:8080/api"
auth = ("admin", "district")
start_iso = "$TASK_START_ISO"

def parse_dhis_date(d_str):
    # Handles "2023-10-27T10:00:00.123" or similar
    try:
        # Simple ISO parse attempt (Python 3.7+)
        return datetime.fromisoformat(d_str.replace('Z', '+00:00'))
    except:
        return datetime.min

try:
    start_dt = parse_dhis_date(start_iso)
    
    # Check Analytics Table tasks
    r_analytics = requests.get(f"{base_url}/system/tasks/ANALYTICS_TABLE", auth=auth)
    r_resource = requests.get(f"{base_url}/system/tasks/RESOURCE_TABLE", auth=auth)
    r_integrity = requests.get(f"{base_url}/system/tasks/DATA_INTEGRITY", auth=auth)
    
    # Also check /api/dataIntegrity/summary which holds last run info
    r_integrity_summary = requests.get(f"{base_url}/dataIntegrity/summary", auth=auth)
    
    analytics_run = False
    integrity_run = False
    
    # Helper to check list of tasks
    def check_tasks(response):
        if response.status_code != 200: return False
        tasks = response.json() # usually list of dicts
        if not isinstance(tasks, list): return False
        for t in tasks:
            # Task format varies, often has 'created' or 'startTime'
            t_time = t.get('created') or t.get('startTime') or t.get('completedTime')
            if t_time:
                dt = parse_dhis_date(t_time)
                if dt >= start_dt:
                    return True
        return False

    if check_tasks(r_analytics) or check_tasks(r_resource):
        analytics_run = True
        
    if check_tasks(r_integrity):
        integrity_run = True
        
    # Fallback for integrity: check if summary has recent 'completedTime'
    # The summary endpoint structure varies by version, but often has info.
    # If explicit task log failed, we assume if the agent produced a report with
    # correct findings, they likely ran it. But we'll try to detect execution.
    
    # If the user accessed the Data Administration app, we might see it in usage stats?
    # Hard to verify without explicit logs. We will rely heavily on the report content
    # if API logs are empty.
    
    print(json.dumps({
        "analytics_triggered": analytics_run,
        "integrity_triggered": integrity_run,
        "task_check_time": datetime.now().isoformat()
    }))

except Exception as e:
    print(json.dumps({"error": str(e), "analytics_triggered": False, "integrity_triggered": False}))
EOF
)

# 5. Get System Info for content verification matching
SYSTEM_INFO=$(dhis2_api "system/info" 2>/dev/null)

# 6. Bundle Result
cat > /tmp/system_health_audit_result.json <<EOF
{
    "task_start_epoch": $TASK_START_EPOCH,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING,
    "report_size_bytes": $REPORT_SIZE,
    "report_content_b64": "$REPORT_CONTENT",
    "api_checks": $SYSTEM_TASKS_JSON,
    "system_info": $SYSTEM_INFO
}
EOF

# Ensure permissions
chmod 666 /tmp/system_health_audit_result.json 2>/dev/null || true

echo "Export complete. Result saved to /tmp/system_health_audit_result.json"