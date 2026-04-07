#!/bin/bash
set -e

echo "=== Exporting reorder_workout_exercises result ==="

source /workspace/scripts/task_utils.sh

# Record task boundaries
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Copy task info into container so export script can read the Day ID
docker cp /tmp/wger_task_info.json wger-web:/tmp/wger_task_info.json

# Create the Python script to fetch the current state
cat > /tmp/wger_export_routine.py << 'EOF'
import json
import sys

from wger.manager.models import Day, Set

try:
    with open('/tmp/wger_task_info.json', 'r') as f:
        info = json.load(f)
    
    day_id = info.get('day_id')

    # Fetch sets ordered by their sequence in the database
    sets = Set.objects.filter(day_id=day_id).order_by('order')
    
    current_sets = []
    for s in sets:
        ex_name = s.setting_set.first().exercise.name if s.setting_set.exists() else 'Unknown'
        current_sets.append({
            'id': s.id,
            'order': s.order,
            'exercise': ex_name
        })
        
    print("JSON_START")
    print(json.dumps({"current_sets": current_sets}))
    print("JSON_END")

except Exception as e:
    print("JSON_START")
    print(json.dumps({"error": str(e)}))
    print("JSON_END")
    sys.exit(1)
EOF

echo "Executing export script inside wger container..."
docker cp /tmp/wger_export_routine.py wger-web:/tmp/wger_export_routine.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/wger_export_routine.py').read())" > /tmp/export_out.txt

# Extract JSON data
sed -n '/JSON_START/,/JSON_END/p' /tmp/export_out.txt | grep -v 'JSON_START' | grep -v 'JSON_END' > /tmp/export_data.json

# Merge initial task info with final state into one result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
try:
    with open('/tmp/wger_task_info.json', 'r') as f:
        info = json.load(f)
    with open('/tmp/export_data.json', 'r') as f:
        data = json.load(f)
        
    info.update(data)
    info['task_start'] = $TASK_START
    info['task_end'] = $TASK_END
    
    with open('$TEMP_JSON', 'w') as f:
        json.dump(info, f, indent=2)
except Exception as e:
    print('Failed to merge JSON data:', e)
"

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="