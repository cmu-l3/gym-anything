#!/bin/bash
set -e
echo "=== Exporting duplicate_training_day task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for visual evidence
take_screenshot /tmp/task_final.png

# Create a Python script to extract the routine's exact structural state
cat > /tmp/wger_export_routine.py << 'PYTHON_EXPORT_EOF'
import json
from django.contrib.auth.models import User
from wger.manager.models import Routine

try:
    admin = User.objects.get(username="admin")
    routine = Routine.objects.filter(name="Push-Pull-Legs Split", user=admin).first()
    
    if not routine:
        print(json.dumps({"routine_exists": False}))
    else:
        data = {"routine_exists": True, "days": {}}
        for d in routine.day_set.all():
            day_data = {"id": d.id, "name": d.name, "slots": []}
            for s in d.setting_set.order_by('order', 'id'):
                slot_data = {
                    "exercise_id": s.exercise.id if s.exercise else None,
                    "exercise_name": s.exercise.name if s.exercise else None,
                    "sets": []
                }
                for st in s.set_set.order_by('order', 'id'):
                    slot_data["sets"].append({"reps": st.reps})
                day_data["slots"].append(slot_data)
            data["days"][d.name] = day_data
        print(json.dumps(data))
except Exception as e:
    print(json.dumps({"error": str(e), "routine_exists": False}))
PYTHON_EXPORT_EOF

# Execute export script and capture JSON output
docker cp /tmp/wger_export_routine.py wger-web:/tmp/wger_export_routine.py
ROUTINE_JSON=$(docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/wger_export_routine.py').read())" 2>/dev/null)

# Create final result container mapping
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "routine_data": $ROUTINE_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Task results successfully exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="