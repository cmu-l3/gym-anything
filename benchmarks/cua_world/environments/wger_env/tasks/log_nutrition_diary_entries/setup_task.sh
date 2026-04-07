#!/bin/bash

echo "=== Setting up log_nutrition_diary_entries task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure wger is responding properly
wait_for_wger_page

# Inject the required ingredients into the DB and clean today's diary to ensure a clean slate
django_shell "
from wger.nutrition.models import Ingredient
import datetime
from django.contrib.auth.models import User

# Ensure exact ingredients exist
Ingredient.objects.get_or_create(name='Rolled Oats', defaults={'energy': 379, 'protein': 13.1, 'carbohydrates': 67.7, 'fat': 6.5})
Ingredient.objects.get_or_create(name='Whole Milk', defaults={'energy': 61, 'protein': 3.2, 'carbohydrates': 4.8, 'fat': 3.3})

# Clean today's diary for admin to prevent pre-existing completion
try:
    try:
        from wger.nutrition.models import NutritionDiary as DiaryModel
    except ImportError:
        from wger.nutrition.models import NutritionLog as DiaryModel
        
    admin = User.objects.get(username='admin')
    DiaryModel.objects.filter(user=admin, date=datetime.date.today()).delete()
    print('Cleaned today diary for admin')
except Exception as e:
    print('Could not clean diary:', e)
"

# Launch Firefox and navigate to the login page
launch_firefox_to "http://localhost/en/user/login" 5

# Take initial screenshot for evidence
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="