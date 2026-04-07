#!/bin/bash
set -e

echo "=== Exporting scale_meal_batch_cooking result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Querying database for meal modifications..."

# Write an extraction script to run inside the django container
cat > /tmp/extract_meals.py << 'EOF'
import json
from django.contrib.auth.models import User
from wger.nutrition.models import NutritionPlan, Meal

try:
    admin = User.objects.get(username='admin')
    plan = NutritionPlan.objects.filter(description='University Athlete Menu', user=admin).first()
    
    result = {
        "plan_exists": plan is not None,
        "original_meal": {"exists": False, "items": {}},
        "new_meal": {"exists": False, "items": {}},
        "other_meals_count": 0
    }
    
    if plan:
        # Check original
        orig = Meal.objects.filter(plan=plan, name__iexact='Performance Bowl (1 Serving)').first()
        if orig:
            items = {item.ingredient.name: float(item.amount) for item in orig.items.all()}
            result['original_meal'] = {"exists": True, "items": items}
            
        # Check new meal
        new_m = Meal.objects.filter(plan=plan, name__iexact='Performance Bowl (25 Servings)').first()
        if new_m:
            items = {item.ingredient.name: float(item.amount) for item in new_m.items.all()}
            result['new_meal'] = {"exists": True, "items": items}
            
        # Count total meals in this plan
        result['other_meals_count'] = Meal.objects.filter(plan=plan).count()
            
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"error": str(e)}))
EOF

# Execute extraction script
docker cp /tmp/extract_meals.py wger-web:/tmp/extract_meals.py
DB_OUTPUT=$(docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/extract_meals.py').read())")

# Wrap DB output with task metadata into final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_state": $DB_OUTPUT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure safe file permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="