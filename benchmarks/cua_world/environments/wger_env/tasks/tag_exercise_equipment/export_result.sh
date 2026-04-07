#!/bin/bash
echo "=== Exporting tag_exercise_equipment task results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Capturing final state screenshot..."
take_screenshot /tmp/task_final.png

# Query final database state of the target exercise
echo "Extracting final database state..."
DB_JSON=$(django_shell "
import json
from wger.exercises.models import Exercise
try:
    ex = Exercise.objects.filter(name='Barbell Hip Thrust (Sports Science)').first()
    if ex:
        eq = list(ex.equipment.values_list('name', flat=True))
        print(json.dumps({'found': True, 'equipment': eq, 'count': len(eq)}))
    else:
        print(json.dumps({'found': False, 'equipment': [], 'count': 0}))
except Exception as e:
    print(json.dumps({'found': False, 'error': str(e)}))
" | grep '{"found":' | tail -n 1)

# Fallback string if python parsing catastrophically fails
if [ -z "$DB_JSON" ]; then
    DB_JSON='{"found": false, "error": "Query failed or returned empty"}'
fi

# Package into clean JSON export using temporary file for safety
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_state": $DB_JSON
}
EOF

# Move to standard exported result path
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON written successfully to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="