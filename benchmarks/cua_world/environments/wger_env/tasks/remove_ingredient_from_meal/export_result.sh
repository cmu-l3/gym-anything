#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png ga

echo "Extracting database state..."

# Create Python script to export current state
cat > /tmp/export_wger_task.py << 'EOF'
import json
from django.contrib.auth.models import User
from wger.nutrition.models import NutritionPlan, Meal, MealItem, Ingredient

admin = User.objects.get(username='admin')

plan_exists = NutritionPlan.objects.filter(user=admin, description='Maintenance Diet').exists()
meal_exists = Meal.objects.filter(plan__user=admin, plan__description='Maintenance Diet', name='Lunch').exists()

cola_in_lunch = False
siblings_in_lunch = 0
lunch_item_count = 0

if meal_exists:
    meal = Meal.objects.get(plan__user=admin, plan__description='Maintenance Diet', name='Lunch')
    lunch_item_count = meal.item_set.count()
    cola_in_lunch = meal.item_set.filter(ingredient__name='Cola Drink').exists()
    siblings_in_lunch = meal.item_set.filter(
        ingredient__name__in=['Chicken Breast Raw', 'Brown Rice Cooked', 'Broccoli Raw']
    ).count()

global_cola_exists = Ingredient.objects.filter(name='Cola Drink').exists()

result = {
    "plan_exists": plan_exists,
    "meal_exists": meal_exists,
    "cola_in_lunch": cola_in_lunch,
    "siblings_in_lunch": siblings_in_lunch,
    "lunch_item_count": lunch_item_count,
    "global_cola_exists": global_cola_exists
}

with open('/tmp/export_result.json', 'w') as f:
    json.dump(result, f)
EOF

# Execute script in container and retrieve result
docker cp /tmp/export_wger_task.py wger-web:/tmp/export_wger_task.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/export_wger_task.py').read())"
docker cp wger-web:/tmp/export_result.json /tmp/task_db_result.json

# Combine with timing metadata
jq --arg start "$TASK_START" --arg end "$TASK_END" \
   '. + {task_start: ($start|tonumber), task_end: ($end|tonumber)}' \
   /tmp/task_db_result.json > /tmp/task_result.json

chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="