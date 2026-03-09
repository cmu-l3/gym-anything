#!/bin/bash
# Task setup: research_cohort_fitness_baseline
# Cleans up stale artifacts, writes the baseline data document,
# records baselines, and launches Firefox to the wger dashboard.

source /workspace/scripts/task_utils.sh

chmod +x /workspace/tasks/research_cohort_fitness_baseline/export_result.sh

echo "=== Setting up research_cohort_fitness_baseline task ==="

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
from django.contrib.auth.models import User
for uname in ['stride26_p001', 'stride26_p002', 'stride26_p003', 'stride26_p004']:
    deleted = User.objects.filter(username=uname).delete()
    print(f'Deleted user {uname}: {deleted}')
" 2>/dev/null || true

docker exec wger-web python3 manage.py shell -c "
from wger.manager.models import Routine
deleted = Routine.objects.filter(name='STRIDE-26 Standardized Exercise Intervention', user__username='admin').delete()
print(f'Deleted routine: {deleted}')
" 2>/dev/null || true

docker exec wger-web python3 manage.py shell -c "
from wger.measurement.models import Category
for name in ['VO2max Estimate', 'Handgrip Strength', 'Single-Leg Balance Time']:
    deleted = Category.objects.filter(name=name, user__username='admin').delete()
    print(f'Deleted measurement category {name}: {deleted}')
" 2>/dev/null || true

docker exec wger-web python3 manage.py shell -c "
from wger.nutrition.models import NutritionPlan
deleted = NutritionPlan.objects.filter(description='STRIDE-26 Standardized Dietary Reference', user__username='admin').delete()
print(f'Deleted nutrition plan: {deleted}')
" 2>/dev/null || true

sleep 1

# ---------------------------------------------------------------------------
# Write the companion baseline data document
# ---------------------------------------------------------------------------
mkdir -p /home/ga/Documents

cat > /home/ga/Documents/stride26_baseline_data.txt << 'DOCEOF'
STRIDE-26 STUDY — BASELINE ASSESSMENT DATA ENTRY SHEET
Research Institution: Carnegie Vance Institute for Population Health
Study Protocol: PROT-2026-STRIDE-003
IRB Approval: CMU-IRB-2025-0884
Assessment Window: 2026-02-02 through 2026-02-05
Study Coordinator: You (logged in as wger admin)
===================================================

SECTION A — PARTICIPANT ENROLLMENT
Register the following 4 study participants as wger users.
Use EXACTLY the credentials listed (assigned by study IT system).

Participant 001:
  First Name:  Helena
  Last Name:   Marsh
  Username:    stride26_p001
  Email:       participant001@stride26study.org
  Password:    Stride26!Baseline
  Assessment date: 2026-02-02

Participant 002:
  First Name:  Darnell
  Last Name:   Okonkwo
  Username:    stride26_p002
  Email:       participant002@stride26study.org
  Password:    Stride26!Baseline
  Assessment date: 2026-02-03

Participant 003:
  First Name:  Fiona
  Last Name:   Tran
  Username:    stride26_p003
  Email:       participant003@stride26study.org
  Password:    Stride26!Baseline
  Assessment date: 2026-02-04

Participant 004:
  First Name:  Marcus
  Last Name:   Delacroix
  Username:    stride26_p004
  Email:       participant004@stride26study.org
  Password:    Stride26!Baseline
  Assessment date: 2026-02-05

SECTION B — STANDARDIZED FITNESS ASSESSMENT BATTERY
Create the following measurement categories in wger (under admin account)
and log each participant's baseline measurement:

CATEGORY 1: "VO2max Estimate"
  Unit: ml/kg/min
  Method: Non-exercise prediction (Uth-Sørensen-Overgaard-Pedersen formula)
  Baseline measurements:
    2026-02-02  (P001 - Helena Marsh)     34.2
    2026-02-03  (P002 - Darnell Okonkwo)  41.8
    2026-02-04  (P003 - Fiona Tran)       28.9
    2026-02-05  (P004 - Marcus Delacroix) 38.5

CATEGORY 2: "Handgrip Strength"
  Unit: kg
  Method: Jamar dynamometer, dominant hand, mean of 3 trials
  Baseline measurements:
    2026-02-02  (P001 - Helena Marsh)     32.4
    2026-02-03  (P002 - Darnell Okonkwo)  38.1
    2026-02-04  (P003 - Fiona Tran)       29.6
    2026-02-05  (P004 - Marcus Delacroix) 35.8

CATEGORY 3: "Single-Leg Balance Time"
  Unit: s
  Method: Unipedal stance, dominant leg, eyes open, max 30s
  Baseline measurements:
    2026-02-02  (P001 - Helena Marsh)     18
    2026-02-03  (P002 - Darnell Okonkwo)  24
    2026-02-04  (P003 - Fiona Tran)       12
    2026-02-05  (P004 - Marcus Delacroix) 21

SECTION C — STANDARDIZED EXERCISE INTERVENTION PROTOCOL
Create the following routine (under admin account):

  Routine Name: "STRIDE-26 Standardized Exercise Intervention"
  Description: "52-week workplace fitness RCT: progressive moderate-intensity aerobic and functional strength protocol"

  Training Days:

  Day 1: "Aerobic Conditioning"
    Day of week: Tuesday
    Exercises: Cycling, Running (search wger exercise database)

  Day 2: "Functional Strength Training"
    Day of week: Thursday
    Exercises: Squats, Lunges, Dumbbell Lateral Raise
    (search wger exercise database for these names)

  Day 3: "Active Mobility Session"
    Day of week: Saturday
    Exercises: Walking (search wger exercise database)

Note: wger day-of-week codes — Monday=1, Tuesday=2, Wednesday=3,
      Thursday=4, Friday=5, Saturday=6, Sunday=7

SECTION D — STANDARDIZED DIETARY REFERENCE
Create the following nutrition plan (under admin account).
This serves as the standardized dietary reference for the intervention arm.

  Plan Description: "STRIDE-26 Standardized Dietary Reference"
  Daily Macro Targets (based on study dietary protocol for 75kg reference adult):
    Energy:        2400 kcal
    Protein:        120 g
    Carbohydrates:  310 g
    Fat:             72 g

  Create the following 4 standardized meal slots within this plan:
    1. "Standardized Breakfast"
    2. "Standardized Lunch"
    3. "Standardized Dinner"
    4. "Post-Exercise Recovery"

END OF BASELINE DATA ENTRY SHEET
DOCEOF

chown ga:ga /home/ga/Documents/stride26_baseline_data.txt 2>/dev/null || true
echo "Baseline data document written to /home/ga/Documents/stride26_baseline_data.txt"

# ---------------------------------------------------------------------------
# Record initial baseline counts
# ---------------------------------------------------------------------------
docker exec wger-web python3 manage.py shell -c "
import json
from django.contrib.auth.models import User
from wger.manager.models import Routine
from wger.measurement.models import Category as MeasureCategory
from wger.nutrition.models import NutritionPlan

admin = User.objects.get(username='admin')
baselines = {
    'total_user_count': User.objects.count(),
    'routine_count': Routine.objects.filter(user=admin).count(),
    'measurement_category_count': MeasureCategory.objects.filter(user=admin).count(),
    'nutrition_plan_count': NutritionPlan.objects.filter(user=admin).count()
}
print(json.dumps(baselines))
" 2>/dev/null > /tmp/research_cohort_initial.json || echo '{"total_user_count":1,"routine_count":0,"measurement_category_count":0,"nutrition_plan_count":0}' > /tmp/research_cohort_initial.json

echo "Baseline counts recorded:"
cat /tmp/research_cohort_initial.json

# Record task start timestamp
date +%s > /tmp/research_cohort_start_ts

# ---------------------------------------------------------------------------
# Launch Firefox to the wger dashboard
# ---------------------------------------------------------------------------
launch_firefox_to "http://localhost/en/dashboard" 5

take_screenshot /tmp/research_cohort_start.png

echo "=== Task setup complete: research_cohort_fitness_baseline ==="
