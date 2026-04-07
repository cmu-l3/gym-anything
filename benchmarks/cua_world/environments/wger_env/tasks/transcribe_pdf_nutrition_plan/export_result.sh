#!/bin/bash
set -e
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final evidence screenshot
take_screenshot /tmp/task_final.png

# Query wger database for the newly created nutrition plan
echo "Extracting Nutrition Plan data from wger DB..."
cat > /tmp/wger_export.py << EOF
import json
import traceback

try:
    from wger.nutrition.models import NutritionPlan, Meal, MealItem
    
    # Find plans matching the description
    plans = NutritionPlan.objects.filter(description__icontains="Nutritionist Protocol")
    
    res = {
        "plan_found": False,
        "meals": [],
        "task_start": ${TASK_START},
        "task_end": ${TASK_END}
    }
    
    if plans.exists():
        # Get the most recently created one
        plan = plans.last()
        res["plan_found"] = True
        res["plan_id"] = plan.id
        res["description"] = plan.description
        
        meals = Meal.objects.filter(plan=plan)
        for m in meals:
            m_data = {"name": m.name, "items": []}
            items = MealItem.objects.filter(meal=m)
            for i in items:
                m_data["items"].append({
                    "ingredient_name": i.ingredient.name,
                    "amount": float(i.amount)
                })
            res["meals"].append(m_data)

except Exception as e:
    res = {
        "plan_found": False,
        "error": str(e),
        "traceback": traceback.format_exc(),
        "task_start": ${TASK_START},
        "task_end": ${TASK_END}
    }

with open('/tmp/wger_export_result.json', 'w') as f:
    json.dump(res, f)
EOF

# Execute script inside container and copy results
docker cp /tmp/wger_export.py wger-web:/tmp/wger_export.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/wger_export.py').read())"
docker cp wger-web:/tmp/wger_export_result.json /tmp/task_result.json

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Exported database state:"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="