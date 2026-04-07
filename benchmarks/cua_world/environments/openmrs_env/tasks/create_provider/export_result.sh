#!/bin/bash
set -e
echo "=== Exporting create_provider results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_PERSON_UUID=$(cat /tmp/target_person_uuid.txt 2>/dev/null || echo "")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Query the Provider table for the specific identifier
echo "Querying Provider 'PROV-8821'..."
PROVIDER_JSON=$(omrs_db_query "
SELECT 
    p.provider_id, 
    p.person_id, 
    p.identifier, 
    p.retired, 
    p.date_created,
    pe.uuid as person_uuid
FROM provider p
JOIN person pe ON p.person_id = pe.person_id
WHERE p.identifier = 'PROV-8821'
LIMIT 1;
" | python3 -c "
import sys, json, datetime

def parse_row(line):
    if not line: return None
    parts = line.strip().split('\t')
    if len(parts) < 6: return None
    return {
        'provider_id': parts[0],
        'person_id': parts[1],
        'identifier': parts[2],
        'retired': parts[3],
        'date_created': parts[4],
        'person_uuid': parts[5]
    }

lines = sys.stdin.readlines()
if lines:
    print(json.dumps(parse_row(lines[0])))
else:
    print('null')
")

# 2. Check for duplicate persons (Alice Bowman)
# If the agent created a NEW person instead of using the existing one, count will increase.
CURRENT_PERSON_COUNT=$(omrs_db_query "SELECT count(*) FROM person_name WHERE given_name='Alice' AND family_name='Bowman' AND voided=0;")
INITIAL_PERSON_COUNT=$(cat /tmp/initial_person_count.txt 2>/dev/null || echo "0")

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "provider_record": $PROVIDER_JSON,
    "target_person_uuid": "$TARGET_PERSON_UUID",
    "initial_person_count": $INITIAL_PERSON_COUNT,
    "current_person_count": $CURRENT_PERSON_COUNT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="