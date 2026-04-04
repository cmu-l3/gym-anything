#!/bin/bash
# Task setup: rehab_exercise_protocol
# Cleans up stale artifacts, writes the companion cardiac rehab protocol document,
# records baselines, and launches Firefox to the wger dashboard.

source /workspace/scripts/task_utils.sh

chmod +x /workspace/tasks/rehab_exercise_protocol/export_result.sh

echo "=== Setting up rehab_exercise_protocol task ==="

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
target_dates = ['2026-01-12','2026-01-19','2026-01-26',
                '2026-02-02','2026-02-09','2026-02-16']
for d in target_dates:
    deleted = WeightEntry.objects.filter(user=admin, date=d).delete()
    print(f'Deleted weight entries for {d}: {deleted}')
" 2>/dev/null || true

docker exec wger-web python3 manage.py shell -c "
from wger.manager.models import Routine
deleted = Routine.objects.filter(name='Phase II Cardiac Rehabilitation Protocol', user__username='admin').delete()
print(f'Deleted routine: {deleted}')
" 2>/dev/null || true

docker exec wger-web python3 manage.py shell -c "
from wger.measurement.models import Category
for name in ['6-Minute Walk Distance', 'Resting Systolic BP', 'Borg RPE Score']:
    deleted = Category.objects.filter(name=name, user__username='admin').delete()
    print(f'Deleted measurement category {name}: {deleted}')
" 2>/dev/null || true

docker exec wger-web python3 manage.py shell -c "
from wger.nutrition.models import NutritionPlan
deleted = NutritionPlan.objects.filter(description='Cardiac Heart-Healthy Eating Plan', user__username='admin').delete()
print(f'Deleted nutrition plan: {deleted}')
" 2>/dev/null || true

sleep 1

# ---------------------------------------------------------------------------
# Write the companion clinical protocol document
# ---------------------------------------------------------------------------
mkdir -p /home/ga/Documents

cat > /home/ga/Documents/cardiac_rehab_protocol.txt << 'DOCEOF'
RIVERSIDE MEDICAL CENTER — CARDIAC REHABILITATION UNIT
PHASE II OUTPATIENT PROGRAM — PATIENT PROTOCOL SPECIFICATION
==============================================================
Patient ID: ADM-2026-001 (tracked under admin account)
Diagnosis:  STEMI with PCI, LVEF 48% at discharge
Clearance:  Phase II outpatient exercise — MET tolerance 4.5
Program:    12-week supervised aerobic + resistance progression
Assigned Physiologist: You (logged in as admin)
==============================================================

SECTION A — PHASE I BODY WEIGHT RECORD
Log the following weekly weigh-ins (kg) that were recorded during
the patient's inpatient Phase I stay. Enter under the admin account.

  Date          Weight (kg)
  2026-01-12    88.5
  2026-01-19    87.8
  2026-01-26    87.2
  2026-02-02    86.9
  2026-02-09    86.4
  2026-02-16    85.8

SECTION B — CLINICAL MEASUREMENT CATEGORIES AND ASSESSMENT DATA
Create the following categories and log all assessment results:

CATEGORY 1: "6-Minute Walk Distance"
  Unit: m
  Assessment dates and results (timed corridor walk test):
    2026-01-14    310
    2026-01-28    342
    2026-02-11    378
    2026-02-25    415
    2026-03-04    448

CATEGORY 2: "Resting Systolic BP"
  Unit: mmHg
  Assessment dates and results (pre-exercise seated BP):
    2026-01-14    148
    2026-01-28    143
    2026-02-11    138
    2026-02-25    134
    2026-03-04    130

CATEGORY 3: "Borg RPE Score"
  Unit: RPE
  Assessment dates and results (post-exercise perceived exertion, 6–20 scale):
    2026-01-14    14
    2026-01-28    13
    2026-02-11    12
    2026-02-25    12
    2026-03-04    11

SECTION C — PHASE II EXERCISE ROUTINE
Create a routine with the following specification:

  Routine Name: "Phase II Cardiac Rehabilitation Protocol"
  Description: "Supervised outpatient cardiac rehab: 12-week progressive aerobic and resistance program"

Add the following training days:

  Day 1: "Aerobic Warm-Up and Walking"
    Day of week: Monday
    Exercises: Walking (search wger exercise database)

  Day 2: "Low-Intensity Resistance Circuit"
    Day of week: Wednesday
    Exercises: Dumbbell Lateral Raise, Bicep Curl
    (search for these exercise names in the wger exercise database)

  Day 3: "Active Recovery and Flexibility"
    Day of week: Friday
    Exercises: Walking (search wger exercise database)

Note: wger day-of-week codes — Monday=1, Tuesday=2, Wednesday=3,
      Thursday=4, Friday=5, Saturday=6, Sunday=7

SECTION D — HEART-HEALTHY NUTRITION PLAN
Create a nutrition plan with:

  Plan Description: "Cardiac Heart-Healthy Eating Plan"
  Daily nutritional targets:
    Energy:        2100 kcal
    Protein:         95 g
    Carbohydrates:  280 g
    Fat:             58 g

These targets are derived from the AHA cardiac diet guidelines for
the patient's body weight, age, and cardiovascular risk profile.

END OF CLINICAL PROTOCOL DOCUMENT
DOCEOF

chown ga:ga /home/ga/Documents/cardiac_rehab_protocol.txt 2>/dev/null || true
echo "Protocol document written to /home/ga/Documents/cardiac_rehab_protocol.txt"

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
" 2>/dev/null > /tmp/rehab_protocol_initial.json || echo '{"weight_entry_count":0,"routine_count":0,"measurement_category_count":0,"nutrition_plan_count":0}' > /tmp/rehab_protocol_initial.json

echo "Baseline counts recorded:"
cat /tmp/rehab_protocol_initial.json

# Record task start timestamp
date +%s > /tmp/rehab_protocol_start_ts

# ---------------------------------------------------------------------------
# Launch Firefox to the wger dashboard
# ---------------------------------------------------------------------------
launch_firefox_to "http://localhost/en/dashboard" 5

take_screenshot /tmp/rehab_protocol_start.png

echo "=== Task setup complete: rehab_exercise_protocol ==="
