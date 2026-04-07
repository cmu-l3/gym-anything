#!/bin/bash
# setup_task.sh — Create a nutrition plan with 3 meals and food items
source /workspace/scripts/task_utils.sh

echo "=== Setting up delete_nutrition_plan_meal task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for wger to be responsive
wait_for_wger_page

# -----------------------------------------------------------------------
# 1. Clean up any previous task artifacts
# -----------------------------------------------------------------------
echo "Cleaning up previous task data..."
django_shell "
from wger.nutrition.models import NutritionPlan
from django.contrib.auth.models import User
admin = User.objects.get(username='admin')
NutritionPlan.objects.filter(user=admin, description='Cafeteria Daily Plan').delete()
print('Cleaned up old Cafeteria Daily Plan(s)')
"

# -----------------------------------------------------------------------
# 2. Create the nutrition plan with 3 meals via Python script
# -----------------------------------------------------------------------
echo "Creating nutrition plan and meals..."
cat << 'EOF' > /tmp/wger_setup.py
import json
from django.contrib.auth.models import User
from wger.nutrition.models import NutritionPlan, Meal, Ingredient, MealItem

admin = User.objects.get(username='admin')

# Create plan
plan = NutritionPlan.objects.create(user=admin, description='Cafeteria Daily Plan')

# Create meals
breakfast = Meal.objects.create(plan=plan, name='Breakfast')
lunch = Meal.objects.create(plan=plan, name='Lunch')
dinner = Meal.objects.create(plan=plan, name='Dinner')

# Ensure we have some ingredients
ingredients = list(Ingredient.objects.filter(status=2)[:9])
if len(ingredients) < 9:
    # Create mock realistic ingredients if DB sync wasn't fully populated
    items = [
        ('Whole Wheat Bread', 265, 9, 49, 3.2),
        ('Scrambled Eggs', 148, 10, 1.6, 11),
        ('Orange Juice', 45, 0.7, 10.4, 0.2),
        ('Grilled Chicken Breast', 165, 31, 0, 3.6),
        ('Brown Rice', 112, 2.3, 24, 0.8),
        ('Mixed Vegetables', 65, 2.6, 13, 0.3),
        ('Salmon Fillet', 208, 20, 0, 13),
        ('Sweet Potato', 86, 1.6, 20, 0.1),
        ('Steamed Broccoli', 35, 2.4, 7.2, 0.4),
    ]
    for name, cal, prot, carb, fat in items:
        ing, _ = Ingredient.objects.get_or_create(
            name=name, language_id=2,
            defaults={'energy': cal, 'protein': prot, 'carbohydrates': carb, 'fat': fat, 'status': 2}
        )
        if ing not in ingredients:
            ingredients.append(ing)

# Add items to meals
MealItem.objects.create(meal=breakfast, ingredient=ingredients[0], amount=100)
MealItem.objects.create(meal=breakfast, ingredient=ingredients[1], amount=150)
MealItem.objects.create(meal=breakfast, ingredient=ingredients[2], amount=200)

MealItem.objects.create(meal=lunch, ingredient=ingredients[3], amount=200)
MealItem.objects.create(meal=lunch, ingredient=ingredients[4], amount=150)
MealItem.objects.create(meal=lunch, ingredient=ingredients[5], amount=100)

MealItem.objects.create(meal=dinner, ingredient=ingredients[6], amount=180)
MealItem.objects.create(meal=dinner, ingredient=ingredients[7], amount=200)
MealItem.objects.create(meal=dinner, ingredient=ingredients[8], amount=150)

# Save IDs for bash context
result = {
    'plan_id': plan.id,
    'breakfast_id': breakfast.id,
    'lunch_id': lunch.id,
    'dinner_id': dinner.id,
    'initial_meal_count': 3
}
with open('/tmp/wger_setup_result.json', 'w') as f:
    json.dump(result, f)
print("Setup script executed successfully.")
EOF

docker cp /tmp/wger_setup.py wger-web:/tmp/wger_setup.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/wger_setup.py').read())"
docker cp wger-web:/tmp/wger_setup_result.json /tmp/wger_setup_result.json

# Parse variables from setup result
PLAN_ID=$(python3 -c "import json; print(json.load(open('/tmp/wger_setup_result.json'))['plan_id'])")
BREAKFAST_ID=$(python3 -c "import json; print(json.load(open('/tmp/wger_setup_result.json'))['breakfast_id'])")
LUNCH_ID=$(python3 -c "import json; print(json.load(open('/tmp/wger_setup_result.json'))['lunch_id'])")
DINNER_ID=$(python3 -c "import json; print(json.load(open('/tmp/wger_setup_result.json'))['dinner_id'])")
INITIAL_MEAL_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/wger_setup_result.json'))['initial_meal_count'])")

# Save context for export script
echo "$PLAN_ID" > /tmp/task_plan_id.txt
echo "$BREAKFAST_ID" > /tmp/task_breakfast_id.txt
echo "$LUNCH_ID" > /tmp/task_lunch_id.txt
echo "$DINNER_ID" > /tmp/task_dinner_id.txt
echo "$INITIAL_MEAL_COUNT" > /tmp/task_initial_meal_count.txt

echo "Plan ID: $PLAN_ID"
echo "Lunch Meal ID (to be deleted): $LUNCH_ID"

# -----------------------------------------------------------------------
# 3. Launch Firefox to the wger dashboard and login
# -----------------------------------------------------------------------
echo "Launching Firefox..."
launch_firefox_to "http://localhost/en/user/login" 8

echo "Logging in as admin..."
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool type --clearmodifiers 'admin'" 2>/dev/null
sleep 0.5
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool key Tab" 2>/dev/null
sleep 0.5
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool type --clearmodifiers 'adminadmin'" 2>/dev/null
sleep 0.5
su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool key Return" 2>/dev/null
sleep 5

# Navigate to dashboard
navigate_to "http://localhost/en/dashboard" 5

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="