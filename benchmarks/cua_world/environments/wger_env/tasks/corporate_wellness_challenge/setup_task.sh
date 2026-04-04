#!/bin/bash
# Task setup: corporate_wellness_challenge
# Sets up a clean state for the corporate wellness challenge task.
# Removes any pre-existing entities, writes the companion briefing document,
# records baseline counts, and launches Firefox to the gym member add page.

source /workspace/scripts/task_utils.sh

# Make export_result.sh executable (Lesson 120)
chmod +x /workspace/tasks/corporate_wellness_challenge/export_result.sh

echo "=== Setting up corporate_wellness_challenge task ==="

# Ensure wger is responding
wait_for_wger_page

# -----------------------------------------------------------------------
# Clean up any pre-existing entities to ensure a deterministic start state
# -----------------------------------------------------------------------

# Delete pre-existing users: maria_chen, david_okonkwo, sarah_patel
docker exec wger-web python3 manage.py shell -c "
from django.contrib.auth.models import User
for uname in ['maria_chen', 'david_okonkwo', 'sarah_patel']:
    deleted, _ = User.objects.filter(username=uname).delete()
    print(f'Deleted {deleted} existing {uname} user(s)')
" 2>/dev/null || echo "Warning: could not clean up existing users"

# Delete pre-existing routines by name
docker exec wger-web python3 manage.py shell -c "
from wger.manager.models import Routine
for rname in ['Cardio Kickstart - Maria', 'Strength Foundations - David', 'Flexibility & Recovery - Sarah']:
    deleted, _ = Routine.objects.filter(name=rname).delete()
    print(f'Deleted {deleted} routine(s) named \"{rname}\"')
" 2>/dev/null || echo "Warning: could not clean up existing routines"

# Delete pre-existing measurement categories named "BMI"
docker exec wger-web python3 manage.py shell -c "
from wger.measure.models import Category as MeasureCategory
deleted, _ = MeasureCategory.objects.filter(name='BMI').delete()
print(f'Deleted {deleted} measurement category(ies) named \"BMI\"')
" 2>/dev/null || echo "Warning: could not clean up measurement categories"

# Delete pre-existing nutrition plans named "Apex Wellness Q1 Team Plan"
docker exec wger-web python3 manage.py shell -c "
from wger.nutrition.models import NutritionPlan
deleted, _ = NutritionPlan.objects.filter(description='Apex Wellness Q1 Team Plan').delete()
print(f'Deleted {deleted} nutrition plan(s) named \"Apex Wellness Q1 Team Plan\"')
" 2>/dev/null || echo "Warning: could not clean up nutrition plans"

sleep 1

# -----------------------------------------------------------------------
# Write the companion briefing document
# -----------------------------------------------------------------------
mkdir -p /home/ga/Documents

cat > /home/ga/Documents/wellness_challenge_brief.txt << 'BRIEFEOF'
APEX MANUFACTURING - CORPORATE WELLNESS CHALLENGE Q1 2026
============================================================

PROGRAM COORDINATOR: Admin (you)
DURATION: 12 weeks
GYM: Default gym (ID 1)

PARTICIPANTS:

1. Maria Chen
   Username: maria_chen
   Email: maria.chen@apexmfg.com
   First name: Maria
   Last name: Chen

2. David Okonkwo
   Username: david_okonkwo
   Email: david.okonkwo@apexmfg.com
   First name: David
   Last name: Okonkwo

3. Sarah Patel
   Username: sarah_patel
   Email: sarah.patel@apexmfg.com
   First name: Sarah
   Last name: Patel

PERSONALIZED ROUTINES (create under admin account):

- Maria Chen: "Cardio Kickstart - Maria"
  Description: "12-week progressive cardio program for improved cardiovascular health"

- David Okonkwo: "Strength Foundations - David"
  Description: "12-week compound lift program building functional strength"

- Sarah Patel: "Flexibility & Recovery - Sarah"
  Description: "12-week mobility and active recovery program"

MEASUREMENT TRACKING:
- Create category: "BMI" with unit "index"

TEAM NUTRITION PLAN:
- Description: "Apex Wellness Q1 Team Plan"
BRIEFEOF

echo "Companion briefing document written to /home/ga/Documents/wellness_challenge_brief.txt"

# -----------------------------------------------------------------------
# Record task start timestamp
# -----------------------------------------------------------------------
date +%s > /tmp/task_start_timestamp

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
" 2>/dev/null > /tmp/corporate_wellness_initial.json || echo '{"user_count":0,"routine_count":0,"measurement_category_count":0,"nutrition_plan_count":0}' > /tmp/corporate_wellness_initial.json

echo "Baseline counts recorded to /tmp/corporate_wellness_initial.json"
cat /tmp/corporate_wellness_initial.json

# -----------------------------------------------------------------------
# Launch Firefox to the gym add-member page
# -----------------------------------------------------------------------
launch_firefox_to "http://localhost/en/gym/1/add-member" 5

# Take a starting screenshot
take_screenshot /tmp/task_corporate_wellness_start.png

echo "=== Task setup complete: corporate_wellness_challenge ==="
