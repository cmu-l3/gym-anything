#!/bin/bash
# Task setup: gym_franchise_onboarding
# Cleans up any pre-existing entities from a previous run, records baseline
# counts, and launches Firefox to the wger dashboard. The agent must navigate
# to each module (user management, routines, nutrition, measurements) on its own.

source /workspace/scripts/task_utils.sh

# Make export_result.sh executable (Lesson 120)
chmod +x /workspace/tasks/gym_franchise_onboarding/export_result.sh

echo "=== Setting up gym_franchise_onboarding task ==="

# Ensure wger is responding
wait_for_wger_page

# -----------------------------------------------------------------------
# Clean up any pre-existing entities to ensure a deterministic start state
# -----------------------------------------------------------------------

# Delete pre-existing users: coach_rivera, coach_nakamura, front_desk_jones, member_williams
docker exec wger-web python3 manage.py shell -c "
from django.contrib.auth.models import User
for uname in ['coach_rivera', 'coach_nakamura', 'front_desk_jones', 'member_williams']:
    deleted, _ = User.objects.filter(username=uname).delete()
    print(f'Deleted {deleted} existing {uname} user(s)')
" 2>/dev/null || echo "Warning: could not clean up existing users"

# Delete pre-existing routines named "New Member Welcome Routine"
docker exec wger-web python3 manage.py shell -c "
from wger.manager.models import Routine
deleted, _ = Routine.objects.filter(name='New Member Welcome Routine').delete()
print(f'Deleted {deleted} routine(s) named \"New Member Welcome Routine\"')
" 2>/dev/null || echo "Warning: could not clean up existing routines"

# Delete pre-existing nutrition plans named "30-Day Transformation Kickstart"
docker exec wger-web python3 manage.py shell -c "
from wger.nutrition.models import NutritionPlan
deleted, _ = NutritionPlan.objects.filter(description='30-Day Transformation Kickstart').delete()
print(f'Deleted {deleted} nutrition plan(s) named \"30-Day Transformation Kickstart\"')
" 2>/dev/null || echo "Warning: could not clean up nutrition plans"

# Delete pre-existing measurement categories named "Body Fat Percentage" or "Lean Muscle Mass"
docker exec wger-web python3 manage.py shell -c "
from wger.measure.models import Category as MeasureCategory
for cname in ['Body Fat Percentage', 'Lean Muscle Mass']:
    deleted, _ = MeasureCategory.objects.filter(name=cname).delete()
    print(f'Deleted {deleted} measurement category(ies) named \"{cname}\"')
" 2>/dev/null || echo "Warning: could not clean up measurement categories"

sleep 1

# -----------------------------------------------------------------------
# Record initial baseline counts for verification
# -----------------------------------------------------------------------
docker exec wger-web python3 manage.py shell -c "
import json
from django.contrib.auth.models import User
from wger.manager.models import Routine
from wger.measure.models import Category as MeasureCategory
from wger.nutrition.models import NutritionPlan

baselines = {
    'user_count': User.objects.count(),
    'routine_count': Routine.objects.count(),
    'measurement_category_count': MeasureCategory.objects.count(),
    'nutrition_plan_count': NutritionPlan.objects.count()
}
print(json.dumps(baselines))
" 2>/dev/null > /tmp/gym_franchise_initial.json || echo '{"user_count":0,"routine_count":0,"measurement_category_count":0,"nutrition_plan_count":0}' > /tmp/gym_franchise_initial.json

echo "Baseline counts recorded to /tmp/gym_franchise_initial.json"
cat /tmp/gym_franchise_initial.json

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# -----------------------------------------------------------------------
# Launch Firefox to the dashboard (agent must navigate to each module)
# -----------------------------------------------------------------------
launch_firefox_to "http://localhost" 5

# Take a starting screenshot
take_screenshot /tmp/task_gym_franchise_onboarding_start.png

echo "=== Task setup complete: gym_franchise_onboarding ==="
