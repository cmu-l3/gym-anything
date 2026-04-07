#!/bin/bash
echo "=== Exporting delete_workout_routine task result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_routine_count.txt 2>/dev/null || echo "3")

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Query Django ORM for final state of routines
echo "Querying database for routines state..."
DB_STATE=$(django_shell "
import json
from wger.manager.models import Routine
from django.contrib.auth.models import User

try:
    admin = User.objects.get(username='admin')
    
    # Check specific routines
    b_exists = Routine.objects.filter(user=admin, name='5x5 Beginner').exists()
    p_exists = Routine.objects.filter(user=admin, name='Push-Pull-Legs').exists()
    u_exists = Routine.objects.filter(user=admin, name='Upper-Lower Split').exists()
    
    # Check total count
    count = Routine.objects.filter(user=admin).count()
    
    print(json.dumps({
        'beginner_exists': b_exists,
        'ppl_exists': p_exists,
        'uls_exists': u_exists,
        'final_count': count
    }))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" | grep "{")

# Handle potential empty output from DB script
if [ -z "$DB_STATE" ]; then
    DB_STATE='{"error": "Failed to parse DB output"}'
fi

# Create JSON result securely via temp file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "db_state": $DB_STATE,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to final location ensuring proper permissions for verifier reading
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="