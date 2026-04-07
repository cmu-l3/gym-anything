#!/bin/bash
echo "=== Exporting result for populate_workout_day ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final state screenshot
take_screenshot /tmp/task_final.png

# Create a Python export script to safely query the Django ORM inside the container
cat > /tmp/wger_export.py << 'EOF'
import json
import sys
from wger.manager.models import Routine, Day, Set, Setting

try:
    routine = Routine.objects.filter(name="Mechanic Strength Program").order_by('-id').first()
    if not routine:
        print("___JSON_START___" + json.dumps({"error": "Routine not found"}))
        sys.exit(0)
    
    day = Day.objects.filter(routine=routine, name__icontains="Upper Body").first()
    if not day:
        print("___JSON_START___" + json.dumps({"error": "Day not found"}))
        sys.exit(0)
    
    sets = Set.objects.filter(day=day)
    exercises_data = []
    
    for s in sets:
        exs = list(s.exercises.all())
        ex_names = [e.name for e in exs]
        
        settings = Setting.objects.filter(set=s)
        config = []
        for st in settings:
            try:
                config.append({"reps": int(st.reps), "sets": int(st.sets)})
            except:
                config.append({"reps": str(st.reps), "sets": str(st.sets)})
                
        exercises_data.append({
            "set_id": s.id,
            "exercise_names": ex_names,
            "config": config
        })
        
    result = {
        "routine_id": routine.id,
        "day_id": day.id,
        "exercise_count": len(sets),
        "exercises": exercises_data
    }
    
    # Prefix ensures clean extraction from stdout
    print("___JSON_START___" + json.dumps(result))
except Exception as e:
    print("___JSON_START___" + json.dumps({"error": str(e)}))
EOF

# Copy script to container and execute it
docker cp /tmp/wger_export.py wger-web:/tmp/wger_export.py
RAW_OUTPUT=$(docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/wger_export.py').read())" 2>/dev/null)

# Extract just the JSON line
DB_RESULT=$(echo "$RAW_OUTPUT" | grep -o "___JSON_START___.*" | sed 's/___JSON_START___//')

if [ -z "$DB_RESULT" ]; then
    DB_RESULT='{"error": "Failed to parse JSON output from database query"}'
fi

# Consolidate results into single file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_result": $DB_RESULT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure safe permissions and placement
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="