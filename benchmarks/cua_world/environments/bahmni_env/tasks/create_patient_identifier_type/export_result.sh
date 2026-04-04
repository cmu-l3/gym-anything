#!/bin/bash
echo "=== Exporting create_patient_identifier_type result ==="

# Source shared Bahmni task utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Authentication details
AUTH="-u ${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}"
API_URL="${OPENMRS_API_URL}"

# 1. Get Initial Count
INITIAL_COUNT=$(cat /tmp/initial_id_type_count.txt 2>/dev/null || echo "0")

# 2. Get Current Count and List
log "Fetching current identifier types..."
JSON_RESPONSE=$(curl -sk $AUTH "${API_URL}/patientidentifiertype?v=full&limit=100")

# Calculate current count
CURRENT_COUNT=$(echo "$JSON_RESPONSE" | python3 -c "import sys, json; print(len(json.load(sys.stdin).get('results', [])))" || echo "0")

log "Counts - Initial: $INITIAL_COUNT, Current: $CURRENT_COUNT"

# 3. Search for the specific created item
# We look for "National Health ID" specifically
TARGET_DATA=$(echo "$JSON_RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
results = data.get('results', [])
target = next((r for r in results if 'national health' in r.get('name', '').lower() or 'national health' in r.get('display', '').lower()), None)
if target:
    print(json.dumps(target))
else:
    print('{}')
")

FOUND_UUID=$(echo "$TARGET_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin).get('uuid', ''))")
FOUND_NAME=$(echo "$TARGET_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin).get('name', ''))")
FOUND_DESC=$(echo "$TARGET_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin).get('description', ''))")
FOUND_RETIRED=$(echo "$TARGET_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin).get('retired', 'false'))")

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "found": $(if [ -n "$FOUND_UUID" ]; then echo "true"; else echo "false"; fi),
    "target_uuid": "$FOUND_UUID",
    "target_name": "$FOUND_NAME",
    "target_description": "$FOUND_DESC",
    "is_retired": $FOUND_RETIRED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="