#!/bin/bash
echo "=== Exporting contractor_audit_and_isolation results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take a screenshot of the final application state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check for the creation of the External Contractors department
EXT_DEPT_ID=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e "SELECT id FROM main_departments WHERE deptname='External Contractors' AND isactive=1 LIMIT 1;" 2>/dev/null | tr -d '[:space:]')

EXT_DEPT_EXISTS="false"
if [ -n "$EXT_DEPT_ID" ] && [ "$EXT_DEPT_ID" != "null" ]; then
    EXT_DEPT_EXISTS="true"
else
    EXT_DEPT_ID="null"
fi

# 3. Pull data for the 8 target contractors
declare -A EMP_ACTIVE
declare -A EMP_DEPT

for i in {31..38}; do
    EMP="EMP0${i}"
    DATA=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e "SELECT isactive, department_id FROM main_users WHERE employeeId='${EMP}' LIMIT 1;" 2>/dev/null)
    
    if [ -n "$DATA" ]; then
        ISACTIVE=$(echo "$DATA" | cut -f1)
        DEPT=$(echo "$DATA" | cut -f2)
        EMP_ACTIVE[$EMP]="${ISACTIVE:-null}"
        EMP_DEPT[$EMP]="${DEPT:-null}"
    else
        EMP_ACTIVE[$EMP]="null"
        EMP_DEPT[$EMP]="null"
    fi
done

# 4. Generate the export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "external_dept_exists": $EXT_DEPT_EXISTS,
  "external_dept_id": $EXT_DEPT_ID,
  "employees": {
    "EMP031": {"isactive": ${EMP_ACTIVE[EMP031]}, "department_id": ${EMP_DEPT[EMP031]}},
    "EMP032": {"isactive": ${EMP_ACTIVE[EMP032]}, "department_id": ${EMP_DEPT[EMP032]}},
    "EMP033": {"isactive": ${EMP_ACTIVE[EMP033]}, "department_id": ${EMP_DEPT[EMP033]}},
    "EMP034": {"isactive": ${EMP_ACTIVE[EMP034]}, "department_id": ${EMP_DEPT[EMP034]}},
    "EMP035": {"isactive": ${EMP_ACTIVE[EMP035]}, "department_id": ${EMP_DEPT[EMP035]}},
    "EMP036": {"isactive": ${EMP_ACTIVE[EMP036]}, "department_id": ${EMP_DEPT[EMP036]}},
    "EMP037": {"isactive": ${EMP_ACTIVE[EMP037]}, "department_id": ${EMP_DEPT[EMP037]}},
    "EMP038": {"isactive": ${EMP_ACTIVE[EMP038]}, "department_id": ${EMP_DEPT[EMP038]}}
  }
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="