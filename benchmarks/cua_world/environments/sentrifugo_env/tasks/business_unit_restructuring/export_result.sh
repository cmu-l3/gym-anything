#!/bin/bash
echo "=== Exporting business_unit_restructuring result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final evidence screenshot
take_screenshot /tmp/task_final.png

# Query 1: Check if new Business Unit was created
BU_EXISTS=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -e \
    "SELECT COUNT(*) FROM main_businessunits WHERE unitname='Acme Corp Technology' AND isactive=1;" | tr -d '[:space:]')

if [ "$BU_EXISTS" -gt 0 ]; then
    BU_CREATED="true"
else
    BU_CREATED="false"
fi

# Query 2: Get a mapping of every active Department to its Business Unit
# Output is JSON dictionary: {"Engineering": "Acme Corp Technology", "Sales": "Acme Corp HQ", ...}
DEPT_MAPPINGS_JSON=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -e \
    "SELECT d.deptname, b.unitname FROM main_departments d JOIN main_businessunits b ON d.unitid = b.id WHERE d.isactive=1;" | python3 -c '
import sys, json
res = {}
for line in sys.stdin:
    parts = line.strip().split("\t")
    if len(parts) == 2:
        res[parts[0]] = parts[1]
print(json.dumps(res))
')

# Create Final JSON Result Object
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "bu_created": $BU_CREATED,
    "department_mappings": $DEPT_MAPPINGS_JSON,
    "app_was_running": $(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")
}
EOF

# Move to standard location securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="