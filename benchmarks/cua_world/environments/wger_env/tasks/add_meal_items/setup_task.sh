#!/bin/bash
set -e
echo "=== Setting up add_meal_items task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure wger is responding
wait_for_wger_page

echo "Creating seed data in wger database..."
# Create a python script to run in the django shell
cat > /tmp/wger_setup_meal.py << 'EOF'
import sys
from django.contrib.auth.models import User
from wger.nutrition.models import Ingredient, NutritionPlan, Meal, MealItem

try:
    admin = User.objects.get(username='admin')

    # Create Ingredients (Ensure they don't already exist or get them)
    chicken, _ = Ingredient.objects.get_or_create(
        name='Chicken Breast Raw', 
        defaults={'energy': 120, 'protein': 22.5, 'carbohydrates': 0.0, 'fat': 2.6}
    )
    rice, _ = Ingredient.objects.get_or_create(
        name='Brown Rice Cooked', 
        defaults={'energy': 123, 'protein': 2.7, 'carbohydrates': 25.6, 'fat': 1.0}
    )
    broccoli, _ = Ingredient.objects.get_or_create(
        name='Broccoli Raw', 
        defaults={'energy': 34, 'protein': 2.8, 'carbohydrates': 6.6, 'fat': 0.4}
    )

    # Status 2 = Approved/Searchable in wger
    chicken.status = 2; chicken.save()
    rice.status = 2; rice.save()
    broccoli.status = 2; broccoli.save()

    # Create Plan
    plan, _ = NutritionPlan.objects.get_or_create(user=admin, description='Shift Day Nutrition')

    # Create Meal
    meal, _ = Meal.objects.get_or_create(plan=plan, name='Lunch')

    # Delete any existing items in this meal to ensure a clean state
    MealItem.objects.filter(meal=meal).delete()

    # Write IDs to a file for the exporter/verifier to read later
    with open('/tmp/meal_setup_info.txt', 'w') as f:
        f.write(f"PLAN_ID={plan.id}\n")
        f.write(f"MEAL_ID={meal.id}\n")
        f.write(f"CHICKEN_ID={chicken.id}\n")
        f.write(f"RICE_ID={rice.id}\n")
        f.write(f"BROCCOLI_ID={broccoli.id}\n")
        
    print("Seed data creation successful.")
except Exception as e:
    print(f"Error during seed data creation: {e}")
EOF

# Execute the script inside the wger-web container
docker cp /tmp/wger_setup_meal.py wger-web:/tmp/wger_setup_meal.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/wger_setup_meal.py').read())"

# Copy the setup info out of the container so export_result.sh can access it
docker cp wger-web:/tmp/meal_setup_info.txt /tmp/meal_setup_info.txt

# Launch Firefox to the nutrition overview page
echo "Launching Firefox..."
launch_firefox_to "http://localhost/en/nutrition/overview/" 5

# Take initial screenshot for evidence
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="