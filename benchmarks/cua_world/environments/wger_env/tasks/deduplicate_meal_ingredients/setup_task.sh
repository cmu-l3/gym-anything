#!/bin/bash
echo "=== Setting up deduplicate_meal_ingredients task ==="

# Source shared wger utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure wger web service is up and responding
wait_for_wger_page

# Use Django ORM to explicitly seed the required meal and duplicated ingredients
echo "Seeding duplicated meal data..."
cat > /tmp/setup_meal.py << 'EOF'
from django.contrib.auth.models import User
from wger.nutrition.models import NutritionPlan, Meal, MealItem, Ingredient

try:
    admin = User.objects.get(username='admin')
    plan, _ = NutritionPlan.objects.get_or_create(user=admin, description='Lean Bulk Plan')
    
    # Reset meal if it existed
    Meal.objects.filter(plan=plan, name='Morning Power Shake').delete()
    meal = Meal.objects.create(plan=plan, name='Morning Power Shake')
    
    # Ensure ingredients exist with realistic macros (USDA data)
    whey, _ = Ingredient.objects.get_or_create(name='Whey Protein Powder', defaults={'energy': 378, 'protein': 80, 'carbohydrates': 3, 'fat': 4, 'user': admin})
    pb, _ = Ingredient.objects.get_or_create(name='Peanut Butter', defaults={'energy': 588, 'protein': 25, 'carbohydrates': 20, 'fat': 50, 'user': admin})
    oat, _ = Ingredient.objects.get_or_create(name='Oat Milk', defaults={'energy': 42, 'protein': 1, 'carbohydrates': 7, 'fat': 1.5, 'user': admin})
    
    # Add items (duplicates injected)
    MealItem.objects.create(meal=meal, ingredient=whey, amount=30)
    MealItem.objects.create(meal=meal, ingredient=whey, amount=30)
    MealItem.objects.create(meal=meal, ingredient=whey, amount=30)
    
    MealItem.objects.create(meal=meal, ingredient=pb, amount=20)
    MealItem.objects.create(meal=meal, ingredient=pb, amount=20)
    
    MealItem.objects.create(meal=meal, ingredient=oat, amount=250)
    
    print("Meal setup successful. Inserted 6 items.")
except Exception as e:
    print(f"Error setting up meal: {e}")
EOF

docker cp /tmp/setup_meal.py wger-web:/tmp/setup_meal.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/setup_meal.py').read())"

# Launch Firefox natively handling snap profiles, direct to nutrition overview
launch_firefox_to "http://localhost/en/nutrition/overview/" 5

# Take initial screenshot of setup application
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="