#!/bin/bash
set -e
echo "=== Exporting add_meal_items result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final state..."
take_screenshot /tmp/task_final.png

# Put meal_setup_info.txt back into the container if it was somehow lost, 
# but it should still be there. Just in case, we'll copy it again.
docker cp /tmp/meal_setup_info.txt wger-web:/tmp/meal_setup_info.txt

echo "Extracting meal items from database..."
# Create an export script for the django shell
cat > /tmp/wger_export_meal.py << 'EOF'
import json
from wger.nutrition.models import MealItem

try:
    # Read meal ID from the setup info
    meal_id = None
    with open('/tmp/meal_setup_info.txt', 'r') as f:
        for line in f:
            if line.startswith('MEAL_ID='):
                meal_id = int(line.strip().split('=')[1])
                break

    if meal_id:
        items = MealItem.objects.filter(meal=meal_id)
        results = []
        for item in items:
            results.append({
                'ingredient_id': item.ingredient_id,
                'amount': float(item.amount)
            })

        out = {'items': results, 'error': None}
    else:
        out = {'items': [], 'error': 'MEAL_ID not found in setup info'}
        
    with open('/tmp/wger_meal_export.json', 'w') as f:
        json.dump(out, f)
except Exception as e:
    with open('/tmp/wger_meal_export.json', 'w') as f:
        json.dump({'items': [], 'error': str(e)}, f)
EOF

# Execute export script and retrieve results
docker cp /tmp/wger_export_meal.py wger-web:/tmp/wger_export_meal.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/wger_export_meal.py').read())"
docker cp wger-web:/tmp/wger_meal_export.json /tmp/wger_meal_export.json

# Combine everything into the final task_result.json
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json

# Parse setup info
setup_info = {}
try:
    with open('/tmp/meal_setup_info.txt', 'r') as f:
        for line in f:
            if '=' in line:
                k, v = line.strip().split('=', 1)
                setup_info[k] = int(v)
except Exception as e:
    setup_info['error'] = str(e)

# Parse export data
export_data = {'items': [], 'error': 'Not loaded'}
try:
    with open('/tmp/wger_meal_export.json', 'r') as f:
        export_data = json.load(f)
except Exception as e:
    export_data['error'] = str(e)

# Construct final result
result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'setup_info': setup_info,
    'exported_items': export_data.get('items', []),
    'export_error': export_data.get('error')
}

with open('$TEMP_JSON', 'w') as f:
    json.dump(result, f, indent=2)
"

# Safely move JSON to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="