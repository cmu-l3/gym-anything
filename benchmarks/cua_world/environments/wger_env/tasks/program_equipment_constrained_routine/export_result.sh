#!/bin/bash
echo "=== Exporting program_equipment_constrained_routine result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Generate a Python script to extract complex relational workout data via Django ORM
cat > /tmp/export_routine_data.py << 'EOF'
import json
import traceback

result = {
    "routine_exists": False,
    "day_exists": False,
    "exercises": [],
    "error": None
}

try:
    from wger.manager.models import Routine, Day, Set, Setting
    from django.contrib.auth.models import User

    routines = Routine.objects.filter(name="Hotel Gym Full Body", user__username='admin')
    if routines.exists():
        routine = routines.last()  # Use latest if multiple exist
        result["routine_exists"] = True

        days = Day.objects.filter(routine=routine, name="Full Body Circuit")
        if days.exists():
            day = days.last()
            result["day_exists"] = True

            # Get all exercise slots (Sets) for this day
            slots = Set.objects.filter(day=day)
            for slot in slots:
                # wger stores exercises via M2M on the Set model
                exercises = slot.exercises.all()
                for exercise in exercises:
                    equip_names = [e.name.lower() for e in exercise.equipment.all()]
                    if not equip_names:
                        equip_names = ["none"]

                    # Get settings (actual physical sets/reps)
                    settings = Setting.objects.filter(set=slot)
                    reps_list = [s.reps for s in settings]

                    result["exercises"].append({
                        "exercise_name": exercise.name,
                        "equipment": equip_names,
                        "sets_count": settings.count(),
                        "reps_list": reps_list
                    })
except Exception as e:
    result["error"] = str(e)
    result["traceback"] = traceback.format_exc()

with open('/tmp/wger_routine_export.json', 'w') as f:
    json.dump(result, f)
EOF

# Copy script to container and execute
echo "Querying wger database..."
docker cp /tmp/export_routine_data.py wger-web:/tmp/export_routine_data.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/export_routine_data.py').read())"

# Bring the JSON back from the container
docker cp wger-web:/tmp/wger_routine_export.json /tmp/wger_routine_export.json 2>/dev/null || true

# Wrap it in our standard result format
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
if [ -f /tmp/wger_routine_export.json ]; then
    python3 -c "
import json
with open('/tmp/wger_routine_export.json', 'r') as f:
    data = json.load(f)
data['task_start'] = $TASK_START
data['task_end'] = $TASK_END
data['screenshot_path'] = '/tmp/task_final.png'
with open('$TEMP_JSON', 'w') as f:
    json.dump(data, f)
"
else
    echo '{"routine_exists": false, "error": "Failed to extract from wger container"}' > "$TEMP_JSON"
fi

# Move safely to final accessible path
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="