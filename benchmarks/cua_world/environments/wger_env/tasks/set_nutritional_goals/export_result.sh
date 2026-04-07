#!/bin/bash
# export_result.sh — Export nutritional goals task result
set -e

echo "=== Exporting set_nutritional_goals task result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Query Database for the goals of 'Lean Bulk Plan'
echo "Querying Database for goal states..."
DB_GOALS_JSON=$(django_shell "
import json
from wger.nutrition.models import NutritionPlan
from django.contrib.auth.models import User
try:
    admin = User.objects.get(username='admin')
    plan = NutritionPlan.objects.filter(user=admin, description='Lean Bulk Plan').first()
    if plan:
        result = {
            'exists': True,
            'id': plan.id,
            'energy': float(plan.goal_energy) if plan.goal_energy else None,
            'protein': float(plan.goal_protein) if plan.goal_protein else None,
            'carbohydrates': float(plan.goal_carbohydrates) if plan.goal_carbohydrates else None,
            'fat': float(plan.goal_fat) if plan.goal_fat else None,
            'fiber': float(plan.goal_fiber) if plan.goal_fiber else None
        }
    else:
        result = {'exists': False}
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({'error': str(e), 'exists': False}))
")

# Query API for the goals of 'Lean Bulk Plan' to ensure consistency
echo "Querying API for goal states..."
API_GOALS_JSON=$(wger_api GET "/api/v2/nutritionplan/?format=json" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    results = data.get('results', [])
    for plan in results:
        if plan.get('description') == 'Lean Bulk Plan':
            print(json.dumps({
                'energy': plan.get('goal_energy'),
                'protein': plan.get('goal_protein'),
                'carbohydrates': plan.get('goal_carbohydrates'),
                'fat': plan.get('goal_fat'),
                'fiber': plan.get('goal_fiber')
            }))
            sys.exit(0)
    print(json.dumps({}))
except Exception as e:
    print(json.dumps({'error': str(e)}))
")

# Combine results into a single JSON file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_goals": $DB_GOALS_JSON,
    "api_goals": $API_GOALS_JSON,
    "screenshot_exists": $([ -f "/tmp/task_final_state.png" ] && echo "true" || echo "false")
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="