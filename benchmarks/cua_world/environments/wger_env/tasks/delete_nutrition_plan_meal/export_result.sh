#!/bin/bash
# export_result.sh — Export task completion state

source /workspace/scripts/task_utils.sh

echo "=== Exporting delete_nutrition_plan_meal task results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PLAN_ID=$(cat /tmp/task_plan_id.txt 2>/dev/null || echo "0")
BREAKFAST_ID=$(cat /tmp/task_breakfast_id.txt 2>/dev/null || echo "0")
LUNCH_ID=$(cat /tmp/task_lunch_id.txt 2>/dev/null || echo "0")
DINNER_ID=$(cat /tmp/task_dinner_id.txt 2>/dev/null || echo "0")
INITIAL_MEAL_COUNT=$(cat /tmp/task_initial_meal_count.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final_state.png

# 2. Check Database State via Python script
cat << EOF > /tmp/wger_export.py
import json
from wger.nutrition.models import NutritionPlan, Meal

plan_id = ${PLAN_ID}
breakfast_id = ${BREAKFAST_ID}
lunch_id = ${LUNCH_ID}
dinner_id = ${DINNER_ID}

result = {
    "plan_exists": NutritionPlan.objects.filter(id=plan_id).exists(),
    "lunch_exists": Meal.objects.filter(id=lunch_id).exists(),
    "breakfast_exists": Meal.objects.filter(id=breakfast_id).exists(),
    "dinner_exists": Meal.objects.filter(id=dinner_id).exists(),
    "current_meal_count": Meal.objects.filter(plan_id=plan_id).count()
}

with open('/tmp/wger_export_result.json', 'w') as f:
    json.dump(result, f)
EOF

docker cp /tmp/wger_export.py wger-web:/tmp/wger_export.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/wger_export.py').read())"
docker cp wger-web:/tmp/wger_export_result.json /tmp/db_result.json

# Extract DB values
PLAN_EXISTS=$(python3 -c "import json; print(str(json.load(open('/tmp/db_result.json'))['plan_exists']).lower())")
LUNCH_EXISTS=$(python3 -c "import json; print(str(json.load(open('/tmp/db_result.json'))['lunch_exists']).lower())")
BREAKFAST_EXISTS=$(python3 -c "import json; print(str(json.load(open('/tmp/db_result.json'))['breakfast_exists']).lower())")
DINNER_EXISTS=$(python3 -c "import json; print(str(json.load(open('/tmp/db_result.json'))['dinner_exists']).lower())")
CURRENT_MEAL_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/db_result.json'))['current_meal_count'])")

# 3. Create final task result JSON
cat << EOF > /tmp/task_result.json
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "plan_id": $PLAN_ID,
    "initial_meal_count": $INITIAL_MEAL_COUNT,
    "current_meal_count": $CURRENT_MEAL_COUNT,
    "plan_exists": $PLAN_EXISTS,
    "lunch_exists": $LUNCH_EXISTS,
    "breakfast_exists": $BREAKFAST_EXISTS,
    "dinner_exists": $DINNER_EXISTS,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

chmod 666 /tmp/task_result.json

echo "Exported results:"
cat /tmp/task_result.json

echo "=== Export complete ==="