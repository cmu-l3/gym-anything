#!/bin/bash
set -e
echo "=== Exporting add_exercise_aliases result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

echo "Querying database for exercise aliases..."

# Query database via Django ORM and export to JSON
DB_RESULT=$(django_shell "
import json
from wger.exercises.models import Exercise, ExerciseAlias

result = {
    'aliases': {},
    'original_names': {},
    'dummies': []
}

targets = [
    ('RDL', 'Romanian Deadlift'),
    ('OHP', 'Overhead Press'),
    ('BSS', 'Bulgarian Split Squat')
]

for alias_str, target_name in targets:
    # Check if the alias is correctly mapped to the target exercise
    alias_exists = ExerciseAlias.objects.filter(alias__iexact=alias_str, exercise__name=target_name).exists()
    result['aliases'][alias_str] = alias_exists
    
    # Check if original exercise still exists with its exact original name
    original_exists = Exercise.objects.filter(name=target_name).exists()
    result['original_names'][target_name] = original_exists
    
    # Check if they created a fake/dummy exercise with the acronym as its name
    if Exercise.objects.filter(name__iexact=alias_str).exists():
        result['dummies'].append(alias_str)

print('JSON_START')
print(json.dumps(result))
print('JSON_END')
")

# Extract the JSON payload from the django_shell output
JSON_PAYLOAD=$(echo "$DB_RESULT" | awk '/JSON_START/{flag=1; next} /JSON_END/{flag=0; next} flag')

# Validate payload or create empty fallback
if [ -z "$JSON_PAYLOAD" ]; then
    JSON_PAYLOAD='{"aliases": {}, "original_names": {}, "dummies": []}'
fi

# Write results to the final file safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_state": $JSON_PAYLOAD
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json:"
cat /tmp/task_result.json
echo "=== Export complete ==="