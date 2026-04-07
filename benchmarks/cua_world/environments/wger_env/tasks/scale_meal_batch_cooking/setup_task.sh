#!/bin/bash
set -e

echo "=== Setting up scale_meal_batch_cooking task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure wger is up
wait_for_wger_page

echo "Seeding database with the specific Nutrition Plan and Meal..."

# Write a Python script to seed the specific scenario, copy to container, and execute
cat > /tmp/seed_meal.py << 'EOF'
from django.contrib.auth.models import User
from wger.nutrition.models import NutritionPlan, Meal, MealItem, Ingredient
from wger.core.models import Language

admin = User.objects.get(username='admin')
en = Language.objects.get(short_name='en')

# Clean up any existing state for this task to ensure idempotency
NutritionPlan.objects.filter(description='University Athlete Menu', user=admin).delete()

# Create Plan
plan = NutritionPlan.objects.create(user=admin, description='University Athlete Menu')

# Create Original Meal
meal = Meal.objects.create(plan=plan, name='Performance Bowl (1 Serving)')

# Create Specific Ingredients using USDA FDC realistic macros
ing_quinoa, _ = Ingredient.objects.get_or_create(name='Quinoa, uncooked', defaults={'user': admin, 'language': en, 'energy': 368, 'protein': 14.1, 'carbohydrates': 64.2, 'fat': 6.07})
ing_salmon, _ = Ingredient.objects.get_or_create(name='Salmon, raw', defaults={'user': admin, 'language': en, 'energy': 208, 'protein': 20.4, 'carbohydrates': 0, 'fat': 13.4})
ing_potato, _ = Ingredient.objects.get_or_create(name='Sweet Potato, raw', defaults={'user': admin, 'language': en, 'energy': 86, 'protein': 1.6, 'carbohydrates': 20.1, 'fat': 0.1})
ing_spinach, _ = Ingredient.objects.get_or_create(name='Spinach, raw', defaults={'user': admin, 'language': en, 'energy': 23, 'protein': 2.9, 'carbohydrates': 3.6, 'fat': 0.4})

# Add ingredients to the single serving meal
MealItem.objects.create(meal=meal, ingredient=ing_quinoa, amount=75)
MealItem.objects.create(meal=meal, ingredient=ing_salmon, amount=180)
MealItem.objects.create(meal=meal, ingredient=ing_potato, amount=200)
MealItem.objects.create(meal=meal, ingredient=ing_spinach, amount=85)

print(f"PLAN_ID={plan.id}")
EOF

# Execute seed script
docker cp /tmp/seed_meal.py wger-web:/tmp/seed_meal.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/seed_meal.py').read())" > /tmp/seed_output.txt

PLAN_ID=$(grep "PLAN_ID=" /tmp/seed_output.txt | cut -d'=' -f2)

if [ -z "$PLAN_ID" ]; then
    echo "ERROR: Failed to seed plan data."
    exit 1
fi

echo "Successfully seeded 'University Athlete Menu' (Plan ID: $PLAN_ID)"

# Launch Firefox directly to the nutrition plan to save boilerplate navigation time
echo "Launching Firefox..."
launch_firefox_to "http://localhost/en/nutritionplan/${PLAN_ID}/view/" 5

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="