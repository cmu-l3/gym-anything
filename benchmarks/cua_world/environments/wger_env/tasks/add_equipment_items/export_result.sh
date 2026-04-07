#!/bin/bash
echo "=== Exporting add_equipment_items task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# Check DB for target items and get current count
# Print cleanly formatted JSON surrounded by markers to avoid Django warning pollution
echo "Querying database state..."
DB_STATE_RAW=$(docker exec wger-web python3 manage.py shell -c "
import json
from wger.exercises.models import Equipment
targets = ['Resistance Bands', 'TRX Suspension Trainer', 'Plyo Box']
found = {t: Equipment.objects.filter(name__iexact=t).exists() for t in targets}
output = {
    'current_count': Equipment.objects.count(),
    'items_found': found
}
print(f'__JSON_START__{json.dumps(output)}__JSON_END__')
" 2>/dev/null)

DB_STATE=$(echo "$DB_STATE_RAW" | grep -o '__JSON_START__.*__JSON_END__' | sed 's/__JSON_START__//' | sed 's/__JSON_END__//')

if [ -z "$DB_STATE" ]; then
    # Fallback if parsing fails
    DB_STATE='{"current_count": 0, "items_found": {}}'
fi

CURRENT_COUNT=$(echo "$DB_STATE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('current_count', 0))" 2>/dev/null || echo "0")

# Create JSON result (use temp file for permission safety)
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "db_state": $DB_STATE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="