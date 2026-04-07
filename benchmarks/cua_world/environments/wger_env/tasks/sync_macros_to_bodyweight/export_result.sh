#!/bin/bash
echo "=== Exporting sync_macros_to_bodyweight results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Extract final state from the database via Django ORM
cat > /tmp/export_state.py << 'EOF'
import json
import os
from django.contrib.auth.models import User
from wger.weight.models import WeightEntry
from wger.nutrition.models import NutritionPlan

result = {
    "latest_weight": 0.0,
    "plan_exists": False,
    "goal_protein": 0.0,
    "goal_carbs": 0.0,
    "goal_fat": 0.0,
    "error": None
}

try:
    admin = User.objects.get(username='admin')
    
    # Get the latest weight
    latest_weight = WeightEntry.objects.filter(user=admin).order_by('-date', '-id').first()
    if latest_weight:
        result["latest_weight"] = float(latest_weight.weight)
        
    # Get the Lean Bulk Plan
    plan = NutritionPlan.objects.filter(user=admin, description='Lean Bulk Plan').first()
    if plan:
        result["plan_exists"] = True
        result["goal_protein"] = float(plan.goal_protein) if plan.goal_protein else 0.0
        result["goal_carbs"] = float(plan.goal_carbohydrates) if plan.goal_carbohydrates else 0.0
        result["goal_fat"] = float(plan.goal_fat) if plan.goal_fat else 0.0

except Exception as e:
    result["error"] = str(e)

with open('/tmp/sync_macros_result_internal.json', 'w') as f:
    json.dump(result, f)
EOF

docker cp /tmp/export_state.py wger-web:/tmp/export_state.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/export_state.py').read())"

# Copy the generated JSON out of the container to the host
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
docker cp wger-web:/tmp/sync_macros_result_internal.json "$TEMP_JSON" 2>/dev/null

# Inject timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Use jq or python to merge timestamps into the JSON
python3 -c "
import json
with open('$TEMP_JSON', 'r') as f: data = json.load(f)
data['task_start'] = $TASK_START
data['task_end'] = $TASK_END
with open('$TEMP_JSON', 'w') as f: json.dump(data, f)
"

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo -e "\n=== Export complete ==="