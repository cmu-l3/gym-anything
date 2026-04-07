#!/bin/bash
set -e
echo "=== Setting up adapt_meal_for_allergies task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure wger is responding
wait_for_wger_page

echo "Seeding database with plan, meal, and ingredients..."
cat > /tmp/setup_wger.py << 'EOF'
import datetime
import json
from django.contrib.auth.models import User
from wger.nutrition.models import NutritionPlan, Meal, MealItem, Ingredient

try:
    admin = User.objects.get(username='admin')

    # Seed all needed ingredients with standard realistic macros
    oats, _ = Ingredient.objects.get_or_create(name='Rolled Oats', defaults={'energy': 389, 'protein': 16.9, 'carbohydrates': 66.3})
    milk, _ = Ingredient.objects.get_or_create(name='Whole Milk', defaults={'energy': 61, 'protein': 3.2, 'carbohydrates': 4.8})
    egg, _ = Ingredient.objects.get_or_create(name='Chicken Egg', defaults={'energy': 143, 'protein': 12.6, 'carbohydrates': 0.7})
    soy, _ = Ingredient.objects.get_or_create(name='Soy Milk', defaults={'energy': 33, 'protein': 2.9, 'carbohydrates': 1.7})
    tofu, _ = Ingredient.objects.get_or_create(name='Firm Tofu', defaults={'energy': 144, 'protein': 15.8, 'carbohydrates': 2.8})

    # Ensure Plan exists
    plan, _ = NutritionPlan.objects.get_or_create(user=admin, description='Standard Dietary Plan')

    # Clear any existing matching meals to avoid duplicate issues from testing
    Meal.objects.filter(plan=plan, name='Morning Breakfast').delete()
    
    # Create the specific meal
    meal = Meal.objects.create(plan=plan, name='Morning Breakfast', time=datetime.time(8, 0))

    # Add the initial items (the ones to be modified/removed)
    MealItem.objects.create(meal=meal, ingredient=oats, amount=50)
    MealItem.objects.create(meal=meal, ingredient=milk, amount=200)
    MealItem.objects.create(meal=meal, ingredient=egg, amount=100)

    # Export the specific meal ID to check during verification (prevents delete/recreate gaming)
    with open('/tmp/initial_state_wger.json', 'w') as f:
        json.dump({'plan_id': plan.id, 'meal_id': meal.id}, f)

    print("Setup complete successfully.")
except Exception as e:
    print(f"Error during setup: {e}")
EOF

# Execute setup script inside the container
docker cp /tmp/setup_wger.py wger-web:/tmp/setup_wger.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/setup_wger.py').read())"

# Copy the generated state file out of the container
docker cp wger-web:/tmp/initial_state_wger.json /tmp/initial_state.json

# Launch Firefox cleanly
launch_firefox_to "http://localhost/en/nutrition/overview/" 5

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="