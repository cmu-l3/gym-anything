#!/bin/bash
echo "=== Exporting add_exercise_image task result ==="
source /workspace/scripts/task_utils.sh

# Take final evidence screenshot
take_screenshot /tmp/task_final.png

# Query the backend to inspect the uploaded image file and database entry
cat > /tmp/export_exercise.py << 'EOF'
import json
import os
from wger.exercises.models import Exercise, ExerciseImage

try:
    ex = Exercise.objects.get(name='Standard Push-up')
    images = ExerciseImage.objects.filter(exercise=ex)
    
    data = {
        'exercise_exists': True,
        'exercise_id': ex.id,
        'image_count': images.count(),
        'images': []
    }
    
    for img in images:
        # Check if the file was physically saved to the correct media path backend
        file_path = img.image.path if img.image else ''
        file_exists = os.path.exists(file_path) if file_path else False
        
        data['images'].append({
            'id': img.id,
            'file_path': file_path,
            'file_exists': file_exists,
            'license': img.license.name if img.license else 'None',
        })
except Exception as e:
    data = {'exercise_exists': False, 'image_count': 0, 'error': str(e)}

with open('/tmp/exercise_image_result.json', 'w') as f:
    json.dump(data, f)
EOF

# Execute extraction script
docker cp /tmp/export_exercise.py wger-web:/tmp/export_exercise.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/export_exercise.py').read())"
docker cp wger-web:/tmp/exercise_image_result.json /tmp/task_result_db.json

# Read timestamp to guard against pre-existing files
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Merge metadata into final result
python3 -c "
import json
try:
    with open('/tmp/task_result_db.json', 'r') as f:
        db_data = json.load(f)
except FileNotFoundError:
    db_data = {}

db_data['task_start'] = $TASK_START
db_data['task_end'] = $TASK_END

with open('/tmp/task_result.json', 'w') as f:
    json.dump(db_data, f)
"

# Set permissions so the verifier host can copy it
chmod 666 /tmp/task_result.json
echo "Export complete. Payload ready for verifier:"
cat /tmp/task_result.json