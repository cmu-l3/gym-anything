#!/bin/bash
# Task setup: add_meal_to_plan
# Creates a "Muscle Building" nutrition plan via API, then navigates to its view page.
# The agent will add a meal named "Pre-Workout Meal" to the plan.

source /workspace/scripts/task_utils.sh

echo "=== Setting up add_meal_to_plan task ==="

# Ensure wger is responding
wait_for_wger_page

# Remove any pre-existing "Muscle Building" plan to ensure clean state
docker exec wger-web python3 manage.py shell -c "
from wger.nutrition.models import NutritionPlan
NutritionPlan.objects.filter(description='Muscle Building', user__username='admin').delete()
print('Cleaned up existing Muscle Building plans')
" 2>/dev/null || true

sleep 1

# Create "Muscle Building" nutrition plan via API
TOKEN=$(get_wger_token)
PLAN_RESPONSE=$(curl -s -L -X POST "http://localhost/api/v2/nutritionplan/" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H 'Content-Type: application/json' \
    -d '{"description": "Muscle Building"}' \
    2>/dev/null)

PLAN_ID=$(echo "$PLAN_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)

if [ -z "$PLAN_ID" ]; then
    echo "ERROR: Failed to create Muscle Building nutrition plan"
    echo "Response: $PLAN_RESPONSE"
    exit 1
fi

echo "Created Muscle Building plan with ID: $PLAN_ID"

# Launch Firefox (handles cold start + snap permissions)
launch_firefox_to "http://localhost/en/nutrition/${PLAN_ID}/view/" 5

# Take a starting screenshot
take_screenshot /tmp/task_add_meal_to_plan_start.png

echo "=== Task setup complete: add_meal_to_plan (plan ID: $PLAN_ID) ==="
