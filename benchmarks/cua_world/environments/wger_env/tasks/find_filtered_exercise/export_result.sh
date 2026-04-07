#!/bin/bash
echo "=== Exporting find_filtered_exercise result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Django ORM to extract actual task results dynamically
# We traverse Routine -> Day -> Setting -> Set -> Exercise -> Muscles/Equipment
cat > /tmp/wger_export.py << 'EOF'
import json
import sys

result = {
    "routine_exists": False,
    "day_exists": False,
    "sets_count": 0,
    "reps_found": [],
    "exercises_found": [],
    "exercise_equipment": [],
    "exercise_muscles": [],
    "error": None
}

try:
    from wger.manager.models import Routine, Day, Setting, Set
    
    routines = Routine.objects.filter(name__iexact="Push-Pull-Legs")
    if routines.exists():
        routine = routines.first()
        result["routine_exists"] = True
        
        days = Day.objects.filter(routine=routine, name__iexact="Pull Day")
        if days.exists():
            result["day_exists"] = True
            day = days.first()
            
            settings = Setting.objects.filter(day=day)
            sets = Set.objects.filter(setting__in=settings)
            
            result["sets_count"] = sets.count()
            result["reps_found"] = [s.reps for s in sets]
            
            # Extract exercises linked to these settings/sets
            exercises = set()
            for st in settings:
                if st.exercise:
                    exercises.add(st.exercise)
            
            for ex in exercises:
                result["exercises_found"].append(ex.name)
                
                # Fetch equipment names
                if hasattr(ex, 'equipment'):
                    for e in ex.equipment.all():
                        result["exercise_equipment"].append(e.name.lower())
                
                # Fetch muscle names
                if hasattr(ex, 'muscles'):
                    for m in ex.muscles.all():
                        result["exercise_muscles"].append(m.name.lower())

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
EOF

docker cp /tmp/wger_export.py wger-web:/tmp/wger_export.py

# Execute the extraction script and capture JSON
TEMP_ORM_JSON=$(mktemp /tmp/orm_result.XXXXXX.json)
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/wger_export.py').read())" > "$TEMP_ORM_JSON"

# Check if Firefox was running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Combine results
TEMP_FINAL_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_FINAL_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "orm_data": $(cat "$TEMP_ORM_JSON")
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_FINAL_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_FINAL_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

# Cleanup
rm -f "$TEMP_ORM_JSON" "$TEMP_FINAL_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="