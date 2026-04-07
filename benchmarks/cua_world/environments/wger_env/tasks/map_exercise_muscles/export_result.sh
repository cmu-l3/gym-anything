#!/bin/bash
echo "=== Exporting map_exercise_muscles task result ==="

source /workspace/scripts/task_utils.sh

# Capture final visual state
take_screenshot /tmp/task_final.png ga

# -----------------------------------------------------------------------
# Query wger database for the exercise's muscle relations
# -----------------------------------------------------------------------
cat > /tmp/export_exercise.py << 'EOF'
import json
from wger.exercises.models import Exercise

try:
    ex = Exercise.objects.get(name='Landmine Reverse Lunge')
    # Extract names of all mapped muscles
    primary = [m.name for m in ex.muscles.all()]
    secondary = [m.name for m in ex.muscles_secondary.all()]
    
    res = {
        'exists': True,
        'id': ex.id,
        'primary': primary,
        'secondary': secondary
    }
except Exercise.DoesNotExist:
    res = {
        'exists': False,
        'id': -1,
        'primary': [],
        'secondary': []
    }
except Exception as e:
    res = {
        'exists': False,
        'error': str(e)
    }

# Print JSON with strict prefix for safe grepping out of Django shell
print(f"JSON_RESULT:{json.dumps(res)}")
EOF

docker cp /tmp/export_exercise.py wger-web:/tmp/export_exercise.py
RAW_OUT=$(docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/export_exercise.py').read())")

# Extract the JSON payload safely
JSON_OUT=$(echo "$RAW_OUT" | grep 'JSON_RESULT:' | sed 's/JSON_RESULT://' | tr -d '\r\n')

if [ -z "$JSON_OUT" ]; then
    JSON_OUT='{"error": "Failed to parse JSON output from Django shell"}'
fi

# Gather metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_ID=$(cat /tmp/initial_exercise_id.txt 2>/dev/null || echo "-1")
INITIAL_ID=$(echo "$INITIAL_ID" | tr -d ' \r\n')

# -----------------------------------------------------------------------
# Combine and save results
# -----------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_id": "$INITIAL_ID",
    "db_result": $JSON_OUT
}
EOF

# Move to final location safely (handle potential permission boundaries)
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json

echo ""
echo "=== Export complete ==="