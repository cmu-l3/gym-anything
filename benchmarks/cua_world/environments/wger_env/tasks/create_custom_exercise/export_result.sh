#!/bin/bash
# Export script: create_custom_exercise

echo "=== Exporting create_custom_exercise result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the Django ORM to get the final state of the expected exercise
echo "Extracting exercise data from database..."

cat > /tmp/export_ex.py << 'EOF'
import json
from wger.exercises.models import Exercise

data = {"exists": False}
try:
    # Get the most recently created exercise matching the name
    ex = Exercise.objects.filter(name__icontains="Sled Push").order_by('id').last()
    
    if ex:
        # Safely get primary and secondary muscles (checking for empty querysets)
        primary_muscles = [m.name_en for m in ex.muscles.all()] if ex.muscles.exists() else []
        secondary_muscles = [m.name_en for m in ex.muscles_secondary.all()] if ex.muscles_secondary.exists() else []
        
        data = {
            "exists": True,
            "id": ex.id,
            "name": ex.name,
            "category": ex.category.name if ex.category else "",
            "description": ex.description,
            "primary_muscles": primary_muscles,
            "secondary_muscles": secondary_muscles
        }
except Exception as e:
    data["error"] = str(e)

with open('/tmp/ex_result.json', 'w') as f:
    json.dump(data, f)
EOF

# Run the extraction script inside the web container
docker cp /tmp/export_ex.py wger-web:/tmp/export_ex.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/export_ex.py').read())"

# Retrieve the result JSON from the container
docker cp wger-web:/tmp/ex_result.json /tmp/task_result.json 2>/dev/null || echo '{"exists": false, "error": "Failed to extract data"}' > /tmp/task_result.json

# Ensure correct permissions for the verifier
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json

echo "Extracted Exercise Data:"
cat /tmp/task_result.json
echo ""

echo "=== Export complete ==="