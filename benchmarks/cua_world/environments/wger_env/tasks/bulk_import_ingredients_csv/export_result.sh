#!/bin/bash
echo "=== Exporting bulk_import_ingredients_csv result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps and initial metrics
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Fetch all ingredients from the wger Django ORM into a JSON array for reliable evaluation
echo "Dumping ingredients database state..."
docker exec wger-web python3 manage.py shell -c "
import json
from wger.nutrition.models import Ingredient

data = []
for ing in Ingredient.objects.all():
    data.append({
        'name': ing.name,
        'energy': float(ing.energy) if ing.energy is not None else 0.0,
        'protein': float(ing.protein) if ing.protein is not None else 0.0,
        'carbohydrates': float(ing.carbohydrates) if ing.carbohydrates is not None else 0.0,
        'fat': float(ing.fat) if ing.fat is not None else 0.0
    })
print(json.dumps(data))
" > /tmp/all_ingredients_raw.json 2>/dev/null

FINAL_COUNT=$(python3 -c "import json; d=json.load(open('/tmp/all_ingredients_raw.json')); print(len(d))" 2>/dev/null || echo "0")
echo "Final ingredient count: $FINAL_COUNT"

# Construct the output JSON result safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "final_count": $FINAL_COUNT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Merge the ingredients dump into the JSON response structure
python3 -c "
import json
try:
    with open('$TEMP_JSON', 'r') as f:
        result = json.load(f)
    with open('/tmp/all_ingredients_raw.json', 'r') as f:
        ingredients = json.load(f)
    result['ingredients'] = ingredients
    with open('$TEMP_JSON', 'w') as f:
        json.dump(result, f)
except Exception as e:
    print('Error merging JSON:', e)
"

# Move safely to final output destination
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

# Cleanup temp files
rm -f "$TEMP_JSON" /tmp/all_ingredients_raw.json

echo "Export complete, JSON mapped to /tmp/task_result.json"