#!/bin/bash
echo "=== Exporting reporting_realignment result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query DB for all target employees using one broad join
RAW_DATA=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e "
SELECT u.employeeId, IFNULL(mu.employeeId, ''), IFNULL(d.deptname, ''), IFNULL(j.jobtitlename, '')
FROM main_users u
LEFT JOIN main_employees_summary es ON u.id = es.user_id
LEFT JOIN main_users mu ON es.reporting_manager = mu.id
LEFT JOIN main_departments d ON u.department_id = d.id
LEFT JOIN main_jobtitles j ON u.jobtitle_id = j.id
WHERE u.employeeId IN ('EMP007', 'EMP009', 'EMP011', 'EMP014', 'EMP010', 'EMP016', 'EMP017');
" 2>/dev/null || true)

# Job title count to ensure it was created and is active
TEAM_LEAD_COUNT=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e "
SELECT COUNT(*) FROM main_jobtitles WHERE jobtitlename='Team Lead' AND isactive=1;
" 2>/dev/null || echo "0")

# Safely build JSON array of employees
EMPLOYEES_JSON="["
while IFS=$'\t' read -r empid mgr dept title; do
    [ -z "$empid" ] && continue
    [ "$EMPLOYEES_JSON" != "[" ] && EMPLOYEES_JSON="$EMPLOYEES_JSON,"
    EMPLOYEES_JSON="$EMPLOYEES_JSON{\"empid\":\"$empid\",\"manager_empid\":\"$mgr\",\"department\":\"$dept\",\"jobtitle\":\"$title\"}"
done <<< "$RAW_DATA"
EMPLOYEES_JSON="$EMPLOYEES_JSON]"

# Write to temporary JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "team_lead_count": $TEAM_LEAD_COUNT,
    "employees": $EMPLOYEES_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely resolving permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="