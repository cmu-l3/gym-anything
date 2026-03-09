#!/bin/bash
# Task setup: athlete_body_composition_program
# Cleans up any pre-existing task artifacts, writes the companion program
# document, records baselines, and launches Firefox to the wger dashboard.

source /workspace/scripts/task_utils.sh

chmod +x /workspace/tasks/athlete_body_composition_program/export_result.sh

echo "=== Setting up athlete_body_composition_program task ==="

# Ensure wger is responding
wait_for_wger_page

TOKEN=$(get_wger_token)
if [ -z "$TOKEN" ]; then
    echo "ERROR: Failed to get wger API token"
    exit 1
fi

# ---------------------------------------------------------------------------
# Clean up any pre-existing task artifacts
# ---------------------------------------------------------------------------

# Delete body weight entries on the target dates
docker exec wger-web python3 manage.py shell -c "
from wger.weight.models import WeightEntry
from django.contrib.auth.models import User
admin = User.objects.get(username='admin')
target_dates = ['2026-02-03', '2026-02-10', '2026-02-17', '2026-02-24', '2026-03-03']
for d in target_dates:
    deleted = WeightEntry.objects.filter(user=admin, date=d).delete()
    print(f'Deleted weight entries for {d}: {deleted}')
" 2>/dev/null || true

# Delete pre-existing routine by name
docker exec wger-web python3 manage.py shell -c "
from wger.manager.models import Routine
deleted = Routine.objects.filter(name='Off-Season Wrestling Strength', user__username='admin').delete()
print(f'Deleted routine: {deleted}')
" 2>/dev/null || true

# Delete pre-existing measurement categories named "Skinfold Sum" or "Grip Strength"
docker exec wger-web python3 manage.py shell -c "
from wger.measurement.models import Category
for name in ['Skinfold Sum', 'Grip Strength']:
    deleted = Category.objects.filter(name=name).delete()
    print(f'Deleted measurement category {name}: {deleted}')
" 2>/dev/null || true

# Delete pre-existing nutrition plan
docker exec wger-web python3 manage.py shell -c "
from wger.nutrition.models import NutritionPlan
deleted = NutritionPlan.objects.filter(description='Wrestling Weight Management - Off-Season', user__username='admin').delete()
print(f'Deleted nutrition plan: {deleted}')
" 2>/dev/null || true

sleep 1

# ---------------------------------------------------------------------------
# Write the companion program document
# ---------------------------------------------------------------------------
mkdir -p /home/ga/Documents

cat > /home/ga/Documents/body_comp_program.txt << 'PROGEOF'
NATIONAL SPORTS PERFORMANCE INSTITUTE
BODY COMPOSITION MONITORING PROGRAM
============================================================
Athlete: Collegiate Wrestler (74 kg weight class, off-season)
Physiologist: Admin (you)
Program Start: 2026-02-03
============================================================

SECTION A — HISTORICAL WEIGH-IN DATA
Log the following body weight entries (in kg) under your admin account:

  Date          Weight (kg)
  2026-02-03    79.4
  2026-02-10    78.9
  2026-02-17    78.2
  2026-02-24    77.8
  2026-03-03    77.1

SECTION B — MEASUREMENT TRACKING CATEGORIES
Create the following measurement categories:

1. Category: "Skinfold Sum"
   Unit: mm

2. Category: "Grip Strength"
   Unit: kg

SECTION C — WORKOUT ROUTINE
Create routine: "Off-Season Wrestling Strength"
Description: "8-week hypertrophy and strength block for 74kg wrestler"

Add these training days:

Day 1: "Upper Push/Pull" (Tuesday)
  Add exercises: Bench Press, Bent Over Barbell Row

Day 2: "Lower Compound" (Thursday)
  Add exercises: Squats, Deadlifts

Day 3: "Full Body Power" (Saturday)
  Add exercises: Power Clean, Push Press

Note: Use the existing exercises from the wger exercise database.
Search for the exercise names listed above.

SECTION D — NUTRITION PLAN
Create nutrition plan with description: "Wrestling Weight Management - Off-Season"
Set the following daily nutritional goals:
  Energy: 2600 kcal
  Protein: 160 g
  Carbohydrates: 300 g
  Fat: 80 g

END OF PROGRAM DOCUMENT
PROGEOF

chown ga:ga /home/ga/Documents/body_comp_program.txt 2>/dev/null || true
echo "Program document written to /home/ga/Documents/body_comp_program.txt"

# ---------------------------------------------------------------------------
# Record initial baseline counts
# ---------------------------------------------------------------------------
docker exec wger-web python3 manage.py shell -c "
import json
from django.contrib.auth.models import User
from wger.weight.models import WeightEntry
from wger.manager.models import Routine
from wger.measurement.models import Category as MeasureCategory
from wger.nutrition.models import NutritionPlan

admin = User.objects.get(username='admin')
baselines = {
    'weight_entry_count': WeightEntry.objects.filter(user=admin).count(),
    'routine_count': Routine.objects.filter(user=admin).count(),
    'measurement_category_count': MeasureCategory.objects.filter(user=admin).count(),
    'nutrition_plan_count': NutritionPlan.objects.filter(user=admin).count()
}
print(json.dumps(baselines))
" 2>/dev/null > /tmp/athlete_body_comp_initial.json || echo '{"weight_entry_count":0,"routine_count":0,"measurement_category_count":0,"nutrition_plan_count":0}' > /tmp/athlete_body_comp_initial.json

echo "Baseline counts recorded:"
cat /tmp/athlete_body_comp_initial.json

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# ---------------------------------------------------------------------------
# Launch Firefox to the wger dashboard
# ---------------------------------------------------------------------------
launch_firefox_to "http://localhost/en/dashboard" 5

# Take starting screenshot
take_screenshot /tmp/task_athlete_body_comp_start.png

echo "=== Task setup complete: athlete_body_composition_program ==="
