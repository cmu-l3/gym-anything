#!/bin/bash
set -e
echo "=== Setting up design_constrained_meal task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Ensure wger is running and ready
wait_for_wger_page

# 3. Seed USDA ingredients and target Nutrition Plan via Django ORM
cat > /tmp/wger_keto_setup.py << 'EOF'
from wger.nutrition.models import Ingredient, NutritionPlan, Meal
from django.contrib.auth.models import User

try:
    admin = User.objects.get(username='admin')
    
    # Ensure Lean Bulk Plan exists
    plan, _ = NutritionPlan.objects.get_or_create(user=admin, description='Lean Bulk Plan')
    
    # Delete any existing Keto Breakfast to guarantee clean state
    Meal.objects.filter(plan=plan, name='Keto Breakfast').delete()
    
    # Real USDA FoodData Central ingredient values per 100g
    ingredients = [
        ('Large Egg Raw', 143, 12.6, 0.7, 9.5),
        ('Bacon Cooked', 541, 37.0, 1.7, 42.0),
        ('Cheddar Cheese', 402, 24.9, 1.3, 33.1),
        ('Oatmeal Dry', 379, 16.9, 66.3, 6.9),
        ('White Bread', 266, 8.9, 49.0, 3.3)
    ]
    
    count = 0
    for name, e, p, c, f in ingredients:
        # status '2' means 'Accepted' (publicly searchable)
        obj, created = Ingredient.objects.get_or_create(
            name=name,
            defaults={
                'energy': e, 
                'protein': p, 
                'carbohydrates': c, 
                'fat': f, 
                'user': admin, 
                'status': '2'
            }
        )
        if created: count += 1
        
    print(f"Plan ID: {plan.id}, Seeded {count} new ingredients.")
    
    # Record max meal ID to prevent gaming (reusing an old meal)
    last_meal = Meal.objects.order_by('-id').first()
    max_id = last_meal.id if last_meal else 0
    with open('/tmp/initial_meal_id.txt', 'w') as f:
        f.write(str(max_id))
        
except Exception as e:
    import traceback
    print(f"Setup Error: {e}")
    traceback.print_exc()
EOF

docker cp /tmp/wger_keto_setup.py wger-web:/tmp/wger_keto_setup.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/wger_keto_setup.py').read())"

# Extract the initial_meal_id written by the script inside the container
docker exec wger-web cat /tmp/initial_meal_id.txt > /tmp/initial_meal_id.txt 2>/dev/null || echo "0" > /tmp/initial_meal_id.txt

# 4. Launch Firefox directly to the Nutrition Plans overview
launch_firefox_to "http://localhost/en/nutrition/overview/" 5

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="