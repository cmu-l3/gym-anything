#!/bin/bash
echo "=== Exporting import_requesters_csv result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_START_MS=$(cat /tmp/task_start_time_ms.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Get current user count
CURRENT_USER_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM aaauser;" 2>/dev/null || echo "0")
INITIAL_USER_COUNT=$(cat /tmp/initial_user_count.txt 2>/dev/null || echo "0")
NEW_USERS_COUNT=$((CURRENT_USER_COUNT - INITIAL_USER_COUNT))

# 2. Verify specific sample user (Elena Corves) to check mapping
# We check 'first_name' specifically. If mapping was wrong (e.g. Full Name -> First Name), first_name might be "Elena Corves"
SAMPLE_USER_DATA=$(sdp_db_exec "SELECT first_name, description FROM aaauser WHERE first_name = 'Elena' AND last_name = 'Corves';" 2>/dev/null || echo "")

SAMPLE_FOUND="false"
SAMPLE_FIRST_NAME=""
SAMPLE_JOB_TITLE=""

if [ -n "$SAMPLE_USER_DATA" ]; then
    SAMPLE_FOUND="true"
    SAMPLE_FIRST_NAME=$(echo "$SAMPLE_USER_DATA" | cut -d'|' -f1)
    SAMPLE_JOB_TITLE=$(echo "$SAMPLE_USER_DATA" | cut -d'|' -f2) # Note: 'description' often holds job title in aaauser or joined table
fi

# 3. Check for Created Departments
# We check if the department "Nebula_Ops" exists
DEPT_EXISTS=$(sdp_db_exec "SELECT COUNT(*) FROM departmentdefinition WHERE deptname = 'Nebula_Ops';" 2>/dev/null || echo "0")

# 4. Verify count of specific imported domain users (stronger check)
IMPORTED_EMAILS_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM aaausercontactinfo WHERE emailid LIKE '%@nebula-logistics.test%';" 2>/dev/null || echo "0")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_user_count": $INITIAL_USER_COUNT,
    "current_user_count": $CURRENT_USER_COUNT,
    "net_new_users": $NEW_USERS_COUNT,
    "imported_email_count": $IMPORTED_EMAILS_COUNT,
    "sample_user": {
        "found": $SAMPLE_FOUND,
        "first_name": "$SAMPLE_FIRST_NAME",
        "job_title": "$SAMPLE_JOB_TITLE"
    },
    "department_created": $([ "$DEPT_EXISTS" -gt 0 ] && echo "true" || echo "false"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="