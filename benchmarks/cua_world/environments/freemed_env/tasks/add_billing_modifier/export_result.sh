#!/bin/bash
echo "=== Exporting add_billing_modifier result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_modifier_end.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

MODIFIER_TABLE=$(cat /tmp/modifier_table_name.txt 2>/dev/null || echo "modifier")
INITIAL_COUNT=$(cat /tmp/initial_modifier_count.txt 2>/dev/null || echo "0")
MAX_ID=$(cat /tmp/initial_modifier_max_id.txt 2>/dev/null || echo "0")

CURRENT_COUNT=$(freemed_query "SELECT COUNT(*) FROM $MODIFIER_TABLE" 2>/dev/null || echo "0")

# Extract all newly inserted rows from the modifier table dynamically
# We output as tab-separated values, then convert to JSON using python3
NEW_ROWS_JSON=$(mysql -u freemed -pfreemed freemed -e "SELECT * FROM $MODIFIER_TABLE WHERE id > $MAX_ID" --batch 2>/dev/null | python3 -c '
import sys, json
lines = sys.stdin.read().strip().split("\n")
if not lines or len(lines) < 2:
    print("[]")
    sys.exit(0)
headers = lines[0].split("\t")
result = []
for line in lines[1:]:
    cols = line.split("\t")
    row = {headers[i]: cols[i] for i in range(min(len(headers), len(cols)))}
    result.append(row)
print(json.dumps(result))
' 2>/dev/null || echo "[]")

# Anti-gaming: Check if the agent just spoofed a patient with the name "95" or "Telemedicine"
SPOOFED_PATIENT=$(freemed_query "SELECT COUNT(*) FROM patient WHERE ptfname LIKE '%95%' OR ptlname LIKE '%95%' OR ptfname LIKE '%Telemedicine%' OR ptlname LIKE '%Telemedicine%'" 2>/dev/null || echo "0")

# Create JSON output
TEMP_JSON=$(mktemp /tmp/modifier_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "modifier_table": "$MODIFIER_TABLE",
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "max_id_initial": $MAX_ID,
    "spoofed_patient_count": $SPOOFED_PATIENT,
    "new_rows": $NEW_ROWS_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safely copy to final destination
rm -f /tmp/add_billing_modifier_result.json 2>/dev/null || sudo rm -f /tmp/add_billing_modifier_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/add_billing_modifier_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/add_billing_modifier_result.json
chmod 666 /tmp/add_billing_modifier_result.json 2>/dev/null || sudo chmod 666 /tmp/add_billing_modifier_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/add_billing_modifier_result.json"
cat /tmp/add_billing_modifier_result.json

echo "=== Export complete ==="