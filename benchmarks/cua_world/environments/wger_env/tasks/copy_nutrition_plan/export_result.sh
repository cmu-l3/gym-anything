#!/bin/bash
echo "=== Exporting copy_nutrition_plan task result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_PLAN_COUNT=$(cat /tmp/initial_plan_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query database for results
echo "Querying database for results..."
DB_RESULTS=$(docker exec wger-web python3 manage.py shell -c "
import json
import datetime
from django.contrib.auth.models import User
from wger.nutrition.models import NutritionPlan, Meal

try:
    admin = User.objects.get(username='admin')
    
    # 1. Original plan stats
    original_plans = NutritionPlan.objects.filter(description='Maintenance Diet', user=admin)
    original_exists = original_plans.exists()
    original_meal_count = 0
    if original_exists:
        original_meal_count = Meal.objects.filter(plan=original_plans.first()).count()
        
    # 2. Copy plan stats
    copy_plans = NutritionPlan.objects.filter(description='High Activity Day Plan', user=admin)
    copy_exists = copy_plans.exists()
    copy_meal_count = 0
    creation_valid = False
    
    if copy_exists:
        copy_plan = copy_plans.order_by('-id').first()
        copy_meal_count = Meal.objects.filter(plan=copy_plan).count()
        
        task_start = datetime.datetime.fromtimestamp(${TASK_START})
        # NutritionPlan creation_date is a DateField, check if it's on or after today
        if copy_plan.creation_date >= task_start.date():
            creation_valid = True
            
    # 3. Current total plan count
    current_plan_count = NutritionPlan.objects.filter(user=admin).count()
    
    results = {
        'original_exists': original_exists,
        'original_meal_count': original_meal_count,
        'copy_exists': copy_exists,
        'copy_meal_count': copy_meal_count,
        'current_plan_count': current_plan_count,
        'creation_valid': creation_valid
    }
    print(json.dumps(results))
    
except Exception as e:
    print(json.dumps({'error': str(e)}))
" 2>/dev/null | grep -E '^\{.*\}$' | tail -1)

if [ -z "$DB_RESULTS" ]; then
    DB_RESULTS="{}"
    echo "Warning: Could not parse database results"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_plan_count": $INITIAL_PLAN_COUNT,
    "db_results": $DB_RESULTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="