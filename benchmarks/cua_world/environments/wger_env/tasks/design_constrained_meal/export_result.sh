#!/bin/bash
set -e
echo "=== Exporting design_constrained_meal result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract initial variables
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MEAL_ID=$(cat /tmp/initial_meal_id.txt 2>/dev/null || echo "0")

# 3. Evaluate the meal via Django ORM to calculate exact macros safely
cat > /tmp/wger_keto_eval.py << EOF
import json
from wger.nutrition.models import NutritionPlan, Meal, MealItem
from django.contrib.auth.models import User

res = {
    'meal_exists': False,
    'meal_id': 0,
    'has_items': False,
    'items_count': 0,
    'protein_g': 0.0,
    'carbs_g': 0.0,
    'fat_g': 0.0,
    'energy_kcal': 0.0,
    'error': None
}

try:
    admin = User.objects.get(username='admin')
    plan = NutritionPlan.objects.get(user=admin, description='Lean Bulk Plan')
    
    # Find the newly created Keto Breakfast
    meal = Meal.objects.filter(plan=plan, name='Keto Breakfast').order_by('-id').first()
    
    if meal:
        res['meal_exists'] = True
        res['meal_id'] = meal.id
        
        items = MealItem.objects.filter(meal=meal)
        res['items_count'] = items.count()
        
        if res['items_count'] > 0:
            res['has_items'] = True
            
            total_p = 0.0
            total_c = 0.0
            total_f = 0.0
            total_e = 0.0
            
            for item in items:
                # wger calculation: macro per 100g * (amount / 100)
                ratio = float(item.amount) / 100.0
                if item.ingredient:
                    total_p += float(item.ingredient.protein) * ratio
                    total_c += float(item.ingredient.carbohydrates) * ratio
                    total_f += float(item.ingredient.fat) * ratio
                    total_e += float(item.ingredient.energy) * ratio
                    
            res['protein_g'] = round(total_p, 2)
            res['carbs_g'] = round(total_c, 2)
            res['fat_g'] = round(total_f, 2)
            res['energy_kcal'] = round(total_e, 2)
            
except Exception as e:
    res['error'] = str(e)

print(json.dumps(res))
EOF

docker cp /tmp/wger_keto_eval.py wger-web:/tmp/wger_keto_eval.py
EVAL_JSON=$(docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/wger_keto_eval.py').read())" | grep "{")

# 4. Construct final result JSON safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "initial_meal_id": $INITIAL_MEAL_ID,
    "db_eval": $EVAL_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Handle permissions safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON generated at /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="