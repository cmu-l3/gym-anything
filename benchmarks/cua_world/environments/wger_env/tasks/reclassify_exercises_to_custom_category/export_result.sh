#!/bin/bash
set -e

echo "=== Exporting reclassify_exercises_to_custom_category result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Evaluate final state using Django ORM inside the container
cat > /tmp/wger_export_check.py << 'EOF'
import json
from wger.exercises.models import ExerciseCategory, Exercise

try:
    cat = ExerciseCategory.objects.get(name='Powerlifting Lifts')
    cat_exists = True
    cat_id = cat.id
except Exception:
    cat_exists = False
    cat_id = None

deadlift_reclassified = False
bench_reclassified = False

if cat_exists:
    # Check if ANY exercise matching 'Deadlift' is in the new category
    deadlift_reclassified = Exercise.objects.filter(name__icontains='Deadlift', category_id=cat_id).exists()
    
    # Check if ANY exercise matching 'Bench Press' is in the new category
    bench_reclassified = Exercise.objects.filter(name__icontains='Bench Press', category_id=cat_id).exists()

with open('/tmp/final_state.json', 'w') as f:
    json.dump({
        "category_exists": cat_exists,
        "deadlift_reclassified": deadlift_reclassified,
        "bench_press_reclassified": bench_reclassified,
        "final_category_count": ExerciseCategory.objects.count()
    }, f)
EOF

echo "Executing final state evaluation in wger container..."
docker cp /tmp/wger_export_check.py wger-web:/tmp/wger_export_check.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/wger_export_check.py').read())"

# Retrieve the final state
docker cp wger-web:/tmp/final_state.json /tmp/final_state.json

# Merge initial and final states into the final task_result.json
python3 -c "
import json
import sys

try:
    with open('/tmp/initial_state.json') as f1, open('/tmp/final_state.json') as f2:
        init_data = json.load(f1)
        final_data = json.load(f2)
        
        merged = {**init_data, **final_data}
        merged['task_start'] = int('$TASK_START')
        merged['task_end'] = int('$TASK_END')
        
    with open('/tmp/task_result.json', 'w') as out:
        json.dump(merged, out)
        
    print('Successfully merged state data.')
except Exception as e:
    print(f'Error merging state data: {e}')
    sys.exit(1)
"

# Set permissions so verifier can read it
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json:"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="