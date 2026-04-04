#!/bin/bash
# Task setup: set_nutrition_goal
# Creates an "Athlete Diet" nutrition plan via API and navigates to its view page.
# The agent will set the energy goal to 2500 kcal.

source /workspace/scripts/task_utils.sh

echo "=== Setting up set_nutrition_goal task ==="

# Ensure wger is responding
wait_for_wger_page

# Remove any pre-existing "Athlete Diet" plan to ensure clean state
docker exec wger-web python3 manage.py shell -c "
from wger.nutrition.models import NutritionPlan
NutritionPlan.objects.filter(description='Athlete Diet', user__username='admin').delete()
print('Cleaned up existing Athlete Diet plans')
" 2>/dev/null || true

sleep 1

# Create "Athlete Diet" nutrition plan via API (no goal_energy set yet)
TOKEN=$(get_wger_token)
PLAN_RESPONSE=$(curl -s -L -X POST "http://localhost/api/v2/nutritionplan/" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H 'Content-Type: application/json' \
    -d '{"description": "Athlete Diet"}' \
    2>/dev/null)

PLAN_ID=$(echo "$PLAN_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)

if [ -z "$PLAN_ID" ]; then
    echo "ERROR: Failed to create Athlete Diet plan"
    echo "Response: $PLAN_RESPONSE"
    exit 1
fi

echo "Created Athlete Diet plan with ID: $PLAN_ID"

# Launch Firefox (handles cold start + snap permissions)
launch_firefox_to "http://localhost/en/nutrition/${PLAN_ID}/view/" 5

# Take a starting screenshot
take_screenshot /tmp/task_set_nutrition_goal_start.png

echo "=== Task setup complete: set_nutrition_goal (plan ID: $PLAN_ID) ==="
