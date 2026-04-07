#!/bin/bash
# setup_task.sh — Set Nutritional Goals Task Setup
set -e

echo "=== Setting up set_nutritional_goals task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for wger to be available
wait_for_wger_page

# Verify the "Lean Bulk Plan" exists; create if missing
PLAN_EXISTS=$(django_shell "
from wger.nutrition.models import NutritionPlan
from django.contrib.auth.models import User
admin = User.objects.get(username='admin')
plans = NutritionPlan.objects.filter(user=admin, description='Lean Bulk Plan')
print(plans.count())
")

if [ "$PLAN_EXISTS" = "0" ]; then
    echo "Creating Lean Bulk Plan..."
    create_nutrition_plan "Lean Bulk Plan"
    sleep 2
fi

# Ensure all goal fields are NULL/zero (clean initial state)
echo "Resetting goals to ensure clean initial state..."
django_shell "
from wger.nutrition.models import NutritionPlan
from django.contrib.auth.models import User
admin = User.objects.get(username='admin')
plan = NutritionPlan.objects.filter(user=admin, description='Lean Bulk Plan').first()
if plan:
    plan.goal_energy = None
    plan.goal_protein = None
    plan.goal_carbohydrates = None
    plan.goal_carbohydrates_sugar = None
    plan.goal_fat = None
    plan.goal_fat_saturated = None
    plan.goal_fiber = None
    plan.goal_sodium = None
    plan.save()
    print(f'Reset goals for plan ID {plan.id}')
"

# Launch Firefox to the login page (logged in as admin)
launch_firefox_to "http://localhost/en/user/login" 8

# Log in as admin
navigate_to "http://localhost/en/user/login" 3
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool type --clearmodifiers 'admin'" 2>/dev/null
sleep 0.3
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool key Tab" 2>/dev/null
sleep 0.2
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool type --clearmodifiers 'adminadmin'" 2>/dev/null
sleep 0.3
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool key Return" 2>/dev/null
sleep 5

# Navigate to nutrition plan overview
navigate_to "http://localhost/en/nutrition/view/" 5

maximize_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="