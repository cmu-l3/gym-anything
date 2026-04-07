#!/bin/bash
echo "=== Exporting dependents task result ==="
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Dynamically find the dependents table
TABLE_NAME=$(docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -N -B -e "SHOW TABLES LIKE '%dependent%';" | head -1 | tr -d '[:space:]')

if [ -n "$TABLE_NAME" ]; then
    # Extract all dependents joined with employee ID. 
    # Output is piped to Python to robustly generate a JSON array.
    DEPENDENTS_JSON=$(docker exec sentrifugo-db mysql -u sentrifugo -psentrifugo123 sentrifugo -B -e "
        SELECT u.employeeId, d.* 
        FROM ${TABLE_NAME} d 
        JOIN main_users u ON d.user_id = u.id;
    " | python3 -c '
import sys, json
lines = sys.stdin.read().strip().split("\n")
if len(lines) <= 1:
    print("[]")
    sys.exit(0)
keys = lines[0].split("\t")
res = []
for line in lines[1:]:
    parts = line.split("\t")
    res.append(dict(zip(keys, parts)))
print(json.dumps(res))
' 2>/dev/null || echo "[]")
else
    DEPENDENTS_JSON="[]"
fi

# Create final JSON result
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "dependents": $DEPENDENTS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="