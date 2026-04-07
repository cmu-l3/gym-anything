#!/bin/bash
echo "=== Setting up copy_nutrition_plan task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for wger to be available
wait_for_wger_page

# -----------------------------------------------------------------------
# Ensure "Maintenance Diet" plan exists and has 3 meals
# -----------------------------------------------------------------------
echo "=== Ensuring Maintenance Diet plan with 3 meals ==="

docker exec wger-web python3 manage.py shell -c "
import json
from django.contrib.auth.models import User
from wger.nutrition.models import NutritionPlan, Meal

try:
    admin = User.objects.get(username='admin')
    
    # Get or create the Maintenance Diet plan
    plan, created = NutritionPlan.objects.get_or_create(
        description='Maintenance Diet',
        user=admin
    )
    print(f'Maintenance Diet plan id={plan.id}, created={created}')
    
    # Ensure exactly 3 meals exist
    meal_names = ['Breakfast', 'Lunch', 'Dinner']
    existing_meals = list(Meal.objects.filter(plan=plan))
    
    # Remove extra meals if any
    for m in existing_meals:
        if m.name not in meal_names:
            m.delete()
    
    # Create missing meals
    for name in meal_names:
        meal, mc = Meal.objects.get_or_create(plan=plan, name=name)
        print(f'  Meal: {name} (id={meal.id}, created={mc})')
        
    meal_count = Meal.objects.filter(plan=plan).count()
    print(f'Total meals in Maintenance Diet: {meal_count}')
except Exception as e:
    print(f'Error setting up meals: {e}')
"

# Remove any existing 'High Activity Day Plan' to ensure clean state
echo "=== Removing any pre-existing 'High Activity Day Plan' ==="
docker exec wger-web python3 manage.py shell -c "
from django.contrib.auth.models import User
from wger.nutrition.models import NutritionPlan
try:
    admin = User.objects.get(username='admin')
    deleted, _ = NutritionPlan.objects.filter(description='High Activity Day Plan', user=admin).delete()
    print(f'Cleaned up: {deleted}')
except Exception as e:
    print(f'Error cleaning up: {e}')
"

# Record initial plan count
INITIAL_PLAN_COUNT=$(docker exec wger-web python3 manage.py shell -c "
from django.contrib.auth.models import User
from wger.nutrition.models import NutritionPlan
admin = User.objects.get(username='admin')
print(NutritionPlan.objects.filter(user=admin).count())
" 2>/dev/null | tail -1 | tr -d '\r')

echo "${INITIAL_PLAN_COUNT}" > /tmp/initial_plan_count.txt
echo "Initial plan count: ${INITIAL_PLAN_COUNT}"

# -----------------------------------------------------------------------
# Launch Firefox to wger dashboard
# -----------------------------------------------------------------------
echo "=== Launching Firefox ==="
launch_firefox_to "http://localhost/en/dashboard" 8

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="