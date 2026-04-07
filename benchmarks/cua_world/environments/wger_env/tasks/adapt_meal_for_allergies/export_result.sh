#!/bin/bash
set -e
echo "=== Exporting adapt_meal_for_allergies task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for VLM/evidence
take_screenshot /tmp/task_final_state.png

# Extract the tracked meal ID
MEAL_ID=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('meal_id', 0))" 2>/dev/null || echo "0")

echo "Querying database for meal state (ID: $MEAL_ID)..."

# Python script to run in the container to extract precise DB state
cat > /tmp/export_wger.py << EOF
import json
from wger.nutrition.models import Meal, MealItem

meal_id = $MEAL_ID
result = {'meal_exists': False, 'items': []}

try:
    meal = Meal.objects.get(id=meal_id)
    result['meal_exists'] = True
    result['meal_name'] = meal.name
    
    # Get all items currently in this meal
    for item in MealItem.objects.filter(meal=meal):
        result['items'].append({
            'ingredient_name': item.ingredient.name,
            'amount': float(item.amount)
        })
except Exception as e:
    result['error'] = str(e)

with open('/tmp/result_wger.json', 'w') as f:
    json.dump(result, f)
EOF

# Execute in container and pull results
docker cp /tmp/export_wger.py wger-web:/tmp/export_wger.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/export_wger.py').read())"

# Move the result to a universally accessible location for the verifier
rm -f /tmp/task_result.json 2>/dev/null || true
docker cp wger-web:/tmp/result_wger.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Results extracted."
cat /tmp/task_result.json
echo "=== Export complete ==="