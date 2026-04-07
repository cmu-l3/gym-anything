#!/bin/bash
echo "=== Exporting deduplicate_meal_ingredients result ==="

source /workspace/scripts/task_utils.sh

# Record task boundaries
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final evidence screenshot
take_screenshot /tmp/task_final.png

# Query Django to check exact count and condition of the specific meal
echo "Querying final meal state..."
cat > /tmp/check_meal.py << 'EOF'
import json
from wger.nutrition.models import Meal, MealItem

result = {
    'meal_exists': False,
    'total_items': 0,
    'whey_count': 0,
    'pb_count': 0,
    'oat_count': 0,
    'items_list': []
}

try:
    meal = Meal.objects.filter(name='Morning Power Shake', plan__user__username='admin').first()
    if meal:
        result['meal_exists'] = True
        items = MealItem.objects.filter(meal=meal)
        result['total_items'] = items.count()
        
        for item in items:
            name = item.ingredient.name
            if 'Whey' in name:
                result['whey_count'] += 1
            elif 'Peanut' in name:
                result['pb_count'] += 1
            elif 'Oat' in name:
                result['oat_count'] += 1
                
            result['items_list'].append({
                'name': name,
                'amount': float(item.amount)
            })
except Exception as e:
    result['error'] = str(e)

with open('/tmp/meal_out.json', 'w') as f:
    json.dump(result, f)
EOF

docker cp /tmp/check_meal.py wger-web:/tmp/check_meal.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/check_meal.py').read())"
docker cp wger-web:/tmp/meal_out.json /tmp/meal_out.json

# Merge extracted meal states with timestamp data
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
try:
    with open('/tmp/meal_out.json', 'r') as f:
        data = json.load(f)
except Exception:
    data = {}
data['task_start'] = $TASK_START
data['task_end'] = $TASK_END
data['screenshot_exists'] = True
with open('$TEMP_JSON', 'w') as f:
    json.dump(data, f)
"

# Handle permissions safely for the verifier on the host
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. State saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="