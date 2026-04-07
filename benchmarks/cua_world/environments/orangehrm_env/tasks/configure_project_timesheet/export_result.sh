#!/bin/bash
echo "=== Exporting configure_project_timesheet results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ETHAN_ID=$(cat /tmp/target_emp_number.txt 2>/dev/null || get_employee_empnum "Ethan" "Davis")
CURRENT_DATE=$(date +%Y-%m-%d)

# 1. Check Customer
CUSTOMER_NAME="Midwest Energy Cooperative"
CUST_JSON=$(docker exec orangehrm-db mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "
    SELECT JSON_OBJECT(
        'id', customer_id,
        'name', name,
        'is_deleted', is_deleted
    ) 
    FROM ohrm_customer 
    WHERE name='${CUSTOMER_NAME}' AND is_deleted=0 
    ORDER BY customer_id DESC LIMIT 1;
" 2>/dev/null)
[ -z "$CUST_JSON" ] && CUST_JSON="null"

# 2. Check Project
PROJECT_NAME="Annual Turbine Maintenance 2024"
PROJ_JSON=$(docker exec orangehrm-db mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "
    SELECT JSON_OBJECT(
        'id', p.project_id,
        'name', p.name,
        'customer_name', c.name,
        'is_deleted', p.is_deleted
    )
    FROM ohrm_project p
    JOIN ohrm_customer c ON p.customer_id = c.customer_id
    WHERE p.name='${PROJECT_NAME}' AND p.is_deleted=0
    ORDER BY p.project_id DESC LIMIT 1;
" 2>/dev/null)
[ -z "$PROJ_JSON" ] && PROJ_JSON="null"

# 3. Check Activities
# Get activities for the project found above
ACT_JSON="[]"
if [ "$PROJ_JSON" != "null" ]; then
    PROJ_ID=$(echo "$PROJ_JSON" | jq -r '.id')
    ACT_JSON=$(docker exec orangehrm-db mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "
        SELECT JSON_ARRAYAGG(JSON_OBJECT(
            'id', activity_id,
            'name', name,
            'is_deleted', is_deleted
        ))
        FROM ohrm_project_activity
        WHERE project_id=${PROJ_ID} AND is_deleted=0;
    " 2>/dev/null)
fi
[ -z "$ACT_JSON" ] && ACT_JSON="[]"

# 4. Check Timesheet
# Find timesheet for Ethan covering today
TIMESHEET_JSON=$(docker exec orangehrm-db mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "
    SELECT JSON_OBJECT(
        'id', timesheet_id,
        'state', state,
        'start_date', start_date,
        'end_date', end_date
    )
    FROM ohrm_timesheet
    WHERE emp_number=${ETHAN_ID} 
    AND '${CURRENT_DATE}' BETWEEN start_date AND end_date
    LIMIT 1;
" 2>/dev/null)
[ -z "$TIMESHEET_JSON" ] && TIMESHEET_JSON="null"

# 5. Check Timesheet Items
ITEMS_JSON="[]"
if [ "$TIMESHEET_JSON" != "null" ]; then
    TS_ID=$(echo "$TIMESHEET_JSON" | jq -r '.id')
    
    # Complex query to get hours per day per activity
    # ohrm_timesheet_item contains: timesheet_id, date, duration, project_id, activity_id
    ITEMS_JSON=$(docker exec orangehrm-db mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "
        SELECT JSON_ARRAYAGG(JSON_OBJECT(
            'date', ti.date,
            'duration', ti.duration,
            'activity_name', pa.name,
            'project_name', p.name
        ))
        FROM ohrm_timesheet_item ti
        JOIN ohrm_project_activity pa ON ti.activity_id = pa.activity_id
        JOIN ohrm_project p ON pa.project_id = p.project_id
        WHERE ti.timesheet_id=${TS_ID}
        ORDER BY ti.date, pa.name;
    " 2>/dev/null)
fi
[ -z "$ITEMS_JSON" ] && ITEMS_JSON="[]"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Combine all into one JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "customer": $CUST_JSON,
    "project": $PROJ_JSON,
    "activities": $ACT_JSON,
    "timesheet": $TIMESHEET_JSON,
    "timesheet_items": $ITEMS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result size: $(stat -c %s /tmp/task_result.json) bytes"
cat /tmp/task_result.json