#!/bin/bash
echo "=== Setting up delete_erroneous_ingredient task ==="
source /workspace/scripts/task_utils.sh

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

wait_for_wger_page

# Use django shell to create the data
echo "Creating correct and typo ingredients..."
django_shell "
from wger.nutrition.models import Ingredient
from django.contrib.auth.models import User
try:
    admin = User.objects.get(username='admin')
    
    # Ensure a clean slate for this specific ingredient
    Ingredient.objects.filter(name='Gold Standard 100% Whey').delete()
    
    # Correct entry
    Ingredient.objects.create(
        name='Gold Standard 100% Whey',
        user=admin,
        energy=373,
        protein=79.5,
        carbohydrates=9.9,
        carbohydrates_sugar=3.0,
        fat=3.3,
        fat_saturated=1.0,
        fibres=0.0,
        sodium=0.2
    )
    
    # Typo entry
    Ingredient.objects.create(
        name='Gold Standard 100% Whey',
        user=admin,
        energy=373,
        protein=7.95,
        carbohydrates=9.9,
        carbohydrates_sugar=3.0,
        fat=3.3,
        fat_saturated=1.0,
        fibres=0.0,
        sodium=0.2
    )
    print('Ingredients setup successful.')
except Exception as e:
    print(f'Error during setup: {e}')
"

# Launch Firefox to wger home
launch_firefox_to "http://localhost/" 5

# Capture initial state screenshot for evidence
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="