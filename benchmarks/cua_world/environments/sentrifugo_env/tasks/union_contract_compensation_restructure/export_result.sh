#!/bin/bash
echo "=== Exporting union_contract_compensation_restructure result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Export the active Pay Grades focusing on the expected Target
PAYGRADES_RAW=$(docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -N -B -e "SELECT CONCAT('{\"id\":', id, ',\"name\":\"', paygradename, '\",\"min\":', IFNULL(minsalary, 0), ',\"max\":', IFNULL(maxsalary, 0), '}') FROM main_paygrades WHERE isactive=1 AND paygradename='Technician - Tier 2';" 2>/dev/null | paste -sd "," -)
PAYGRADES_JSON="[${PAYGRADES_RAW}]"

# Export the active Salary Components focusing on the expected Targets
COMPONENTS_RAW=$(docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -N -B -e "SELECT CONCAT('{\"id\":', id, ',\"name\":\"', componentname, '\",\"type\":', IFNULL(QUOTE(componenttype), 'null'), '}') FROM main_salarycomponents WHERE isactive=1 AND componentname IN ('Shift Differential', 'Union Dues - Local 104');" 2>/dev/null | paste -sd "," -)
COMPONENTS_JSON="[${COMPONENTS_RAW}]"

# Retrieve Pay Grade assignments for the two target employees
PAYGRADE_COL=$(docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -N -B -e "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME='main_empsalary' AND COLUMN_NAME LIKE '%paygrade%' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
if [ -z "$PAYGRADE_COL" ]; then PAYGRADE_COL="paygrade_id"; fi

EMP013_UID=$(docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -N -B -e "SELECT id FROM main_users WHERE employeeId='EMP013' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
EMP018_UID=$(docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -N -B -e "SELECT id FROM main_users WHERE employeeId='EMP018' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')

EMP013_PG=$(docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -N -B -e "SELECT ${PAYGRADE_COL} FROM main_empsalary WHERE user_id=${EMP013_UID:-0} LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
EMP018_PG=$(docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -N -B -e "SELECT ${PAYGRADE_COL} FROM main_empsalary WHERE user_id=${EMP018_UID:-0} LIMIT 1;" 2>/dev/null | tr -d '[:space:]')

APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "paygrades": $PAYGRADES_JSON,
    "components": $COMPONENTS_JSON,
    "emp013_pg": "$EMP013_PG",
    "emp018_pg": "$EMP018_PG",
    "app_was_running": $APP_RUNNING
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="