#!/bin/bash
# Task setup: endurance_athlete_periodization
# Cleans up stale artifacts, writes the companion program document,
# records baselines, and launches Firefox to the wger dashboard.

source /workspace/scripts/task_utils.sh

chmod +x /workspace/tasks/endurance_athlete_periodization/export_result.sh

echo "=== Setting up endurance_athlete_periodization task ==="

wait_for_wger_page

TOKEN=$(get_wger_token)
if [ -z "$TOKEN" ]; then
    echo "ERROR: Failed to get wger API token"
    exit 1
fi

# ---------------------------------------------------------------------------
# Clean up any pre-existing task artifacts
# ---------------------------------------------------------------------------

docker exec wger-web python3 manage.py shell -c "
from wger.weight.models import WeightEntry
from django.contrib.auth.models import User
admin = User.objects.get(username='admin')
target_dates = ['2026-01-06','2026-01-13','2026-01-20','2026-01-27',
                '2026-02-03','2026-02-10','2026-02-17','2026-02-24']
for d in target_dates:
    deleted = WeightEntry.objects.filter(user=admin, date=d).delete()
    print(f'Deleted weight entries for {d}: {deleted}')
" 2>/dev/null || true

docker exec wger-web python3 manage.py shell -c "
from wger.manager.models import Routine
deleted = Routine.objects.filter(name='16-Week Marathon Spring Periodization', user__username='admin').delete()
print(f'Deleted routine: {deleted}')
" 2>/dev/null || true

docker exec wger-web python3 manage.py shell -c "
from wger.measurement.models import Category
for name in ['Cooper Test Distance', 'Resting Heart Rate']:
    deleted = Category.objects.filter(name=name, user__username='admin').delete()
    print(f'Deleted measurement category {name}: {deleted}')
" 2>/dev/null || true

docker exec wger-web python3 manage.py shell -c "
from wger.nutrition.models import NutritionPlan
deleted = NutritionPlan.objects.filter(description='Marathon Competition Phase - Race Week', user__username='admin').delete()
print(f'Deleted nutrition plan: {deleted}')
" 2>/dev/null || true

sleep 1

# ---------------------------------------------------------------------------
# Write the companion program document
# ---------------------------------------------------------------------------
mkdir -p /home/ga/Documents

cat > /home/ga/Documents/marathon_periodization_plan.txt << 'PROGEOF'
NATIONAL ENDURANCE PERFORMANCE LAB
MARATHON SPRING PERIODIZATION SPECIFICATION
============================================================
Athlete: Elite Marathon Runner (admin account)
Exercise Physiologist: You (logged in as admin)
Plan Cycle: January–May 2026
Objective: Spring marathon preparation (goal: sub-2:45 finish)
============================================================

SECTION A — BODY WEIGHT HISTORY
Log the following body weight entries (kg) under the admin account.
These represent weekly weigh-ins during the winter base phase:

  Date          Weight (kg)
  2026-01-06    68.2
  2026-01-13    67.9
  2026-01-20    67.5
  2026-01-27    67.8
  2026-02-03    67.4
  2026-02-10    67.1
  2026-02-17    66.8
  2026-02-24    66.5

Note: All entries are in kilograms (kg).

SECTION B — PHYSIOLOGICAL MEASUREMENT CATEGORIES AND DATA
Create the following measurement categories and log historical entries:

CATEGORY 1: "Cooper Test Distance"
  Unit: m
  Historical entries (bi-weekly 12-minute run test results):
    2026-01-10    3420
    2026-01-24    3465
    2026-02-07    3510
    2026-02-21    3555

CATEGORY 2: "Resting Heart Rate"
  Unit: bpm
  Historical entries (morning resting HR, bi-weekly):
    2026-01-10    52
    2026-01-24    51
    2026-02-07    50
    2026-02-21    49

SECTION C — PERIODIZED TRAINING ROUTINE
Create a routine with the following specification:

  Routine Name: "16-Week Marathon Spring Periodization"
  Description: "Elite marathon runner spring race preparation: Base, Build, Peak, Taper phases"

Add the following training days (with correct day-of-week assignments):

  Day 1: "Base Phase - Long Run"
    Day of week: Sunday
    Exercises to add: Running (search in exercise database)

  Day 2: "Base Phase - Easy Recovery"
    Day of week: Wednesday
    Exercises to add: Walking (search in exercise database)

  Day 3: "Build Phase - Tempo Work"
    Day of week: Tuesday
    Exercises to add: Running, Cycling (search in exercise database)

  Day 4: "Build Phase - Long Intervals"
    Day of week: Friday
    Exercises to add: Running (search in exercise database)

  Day 5: "Peak Phase - Race Pace"
    Day of week: Tuesday
    Exercises to add: Running (search in exercise database)

  Day 6: "Taper Phase - Shakeout"
    Day of week: Friday
    Exercises to add: Running, Walking (search in exercise database)

Note: wger day-of-week codes: Monday=1, Tuesday=2, Wednesday=3,
      Thursday=4, Friday=5, Saturday=6, Sunday=7

SECTION D — COMPETITION NUTRITION PLAN
Create a nutrition plan with the following specification:

  Plan Description: "Marathon Competition Phase - Race Week"
  Daily nutritional goals:
    Energy:        3200 kcal
    Protein:        145 g
    Carbohydrates:  480 g
    Fat:             75 g

NOTE: Set these as the daily GOAL values in the nutrition plan settings,
not as actual food log entries.

END OF SPECIFICATION DOCUMENT
PROGEOF

chown ga:ga /home/ga/Documents/marathon_periodization_plan.txt 2>/dev/null || true
echo "Specification document written to /home/ga/Documents/marathon_periodization_plan.txt"

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
" 2>/dev/null > /tmp/endurance_periodization_initial.json || echo '{"weight_entry_count":0,"routine_count":0,"measurement_category_count":0,"nutrition_plan_count":0}' > /tmp/endurance_periodization_initial.json

echo "Baseline counts recorded:"
cat /tmp/endurance_periodization_initial.json

# Record task start timestamp
date +%s > /tmp/endurance_periodization_start_ts

# ---------------------------------------------------------------------------
# Launch Firefox to the wger dashboard
# ---------------------------------------------------------------------------
launch_firefox_to "http://localhost/en/dashboard" 5

take_screenshot /tmp/endurance_periodization_start.png

echo "=== Task setup complete: endurance_athlete_periodization ==="
