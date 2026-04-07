#!/bin/bash
echo "=== Setting up remove_ingredient_from_meal task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure wger is responding
wait_for_wger_page

echo "Injecting target data into wger database..."

# Create Python script to populate database using Django ORM
cat > /tmp/setup_wger_task.py << 'EOF'
import os
import django
from django.contrib.auth.models import User
from wger.nutrition.models import NutritionPlan, Meal, MealItem, Ingredient

admin = User.objects.get(username='admin')

# 1. Create ingredients if they don't exist
chicken, _ = Ingredient.objects.get_or_create(
    name='Chicken Breast Raw', 
    defaults={'energy': 120, 'protein': 22.5, 'carbohydrates': 0, 'fat': 2.6}
)
rice, _ = Ingredient.objects.get_or_create(
    name='Brown Rice Cooked', 
    defaults={'energy': 123, 'protein': 2.7, 'carbohydrates': 25.6, 'fat': 1.0}
)
broccoli, _ = Ingredient.objects.get_or_create(
    name='Broccoli Raw', 
    defaults={'energy': 34, 'protein': 2.8, 'carbohydrates': 6.6, 'fat': 0.4}
)
cola, _ = Ingredient.objects.get_or_create(
    name='Cola Drink', 
    defaults={'energy': 42, 'protein': 0, 'carbohydrates': 10.6, 'fat': 0}
)

# 2. Clean up old plan if it exists to ensure clean state
NutritionPlan.objects.filter(user=admin, description='Maintenance Diet').delete()

# 3. Create Plan & Meal
plan = NutritionPlan.objects.create(user=admin, description='Maintenance Diet')
meal = Meal.objects.create(plan=plan, name='Lunch')

# 4. Add items to meal
MealItem.objects.create(meal=meal, ingredient=chicken, amount=200)
MealItem.objects.create(meal=meal, ingredient=rice, amount=150)
MealItem.objects.create(meal=meal, ingredient=broccoli, amount=100)
MealItem.objects.create(meal=meal, ingredient=cola, amount=330)

print(f"Data seeded successfully. Plan ID: {plan.id}, Meal ID: {meal.id}")
EOF

# Execute script inside container
docker cp /tmp/setup_wger_task.py wger-web:/tmp/setup_wger_task.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/setup_wger_task.py').read())"

# Launch Firefox and navigate to nutrition overview
echo "Launching Firefox..."
launch_firefox_to "http://localhost/en/nutrition/overview/" 5

# Take initial screenshot showing start state
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="