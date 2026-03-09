#!/bin/bash
# Task setup: corporate_health_screening_program
# Cleans up stale artifacts, writes the enrollment brief,
# records baselines, and launches Firefox to the wger dashboard.

source /workspace/scripts/task_utils.sh

chmod +x /workspace/tasks/corporate_health_screening_program/export_result.sh

echo "=== Setting up corporate_health_screening_program task ==="

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
for uname in ['dwilliams_meridian', 'rparker_meridian', 'lchavez_meridian']:
    deleted = User.objects.filter(username=uname).delete()
    print(f'Deleted user {uname}: {deleted}')
" 2>/dev/null || true

docker exec wger-web python3 manage.py shell -c "
from wger.manager.models import Routine
deleted = Routine.objects.filter(name='Meridian Ergonomic Wellness Circuit', user__username='admin').delete()
print(f'Deleted routine: {deleted}')
" 2>/dev/null || true

docker exec wger-web python3 manage.py shell -c "
from wger.nutrition.models import NutritionPlan
deleted = NutritionPlan.objects.filter(description='Meridian Metabolic Risk Reduction Plan', user__username='admin').delete()
print(f'Deleted nutrition plan: {deleted}')
" 2>/dev/null || true

docker exec wger-web python3 manage.py shell -c "
from wger.measurement.models import Category
for name in ['Waist Circumference', 'Resting Heart Rate']:
    deleted = Category.objects.filter(name=name, user__username='admin').delete()
    print(f'Deleted measurement category {name}: {deleted}')
" 2>/dev/null || true

sleep 1

# ---------------------------------------------------------------------------
# Write the companion enrollment brief
# ---------------------------------------------------------------------------
mkdir -p /home/ga/Documents

cat > /home/ga/Documents/occ_health_enrollment_brief.txt << 'DOCEOF'
MERIDIAN INDUSTRIAL SERVICES — OCCUPATIONAL HEALTH DEPARTMENT
EMPLOYEE WELLNESS PROGRAM — ENROLLMENT BRIEF
==============================================================
Program: Cardiovascular Risk Reduction (12-week pilot)
Coordinator: You (logged in as wger admin)
Screening Date: 2026-03-07
Clinic: Meridian OHC, Building 4, Bay 2A
==============================================================

SECTION A — EMPLOYEE ENROLLMENT
Register the following 3 employees in wger. Use EXACTLY the
credentials listed (they are pre-assigned by IT):

Employee 1:
  First Name:  Derek
  Last Name:   Williams
  Username:    dwilliams_meridian
  Email:       d.williams@meridian-ind.com
  Password:    WellnessM2026!
  Role:        Member of gym (Default gym, ID 1)
  Screening results: BMI 31.2, BP 142/88, LDL 3.8 mmol/L

Employee 2:
  First Name:  Ruth
  Last Name:   Parker
  Username:    rparker_meridian
  Email:       r.parker@meridian-ind.com
  Password:    WellnessM2026!
  Role:        Member of gym (Default gym, ID 1)
  Screening results: BMI 29.7, BP 138/84, LDL 3.5 mmol/L

Employee 3:
  First Name:  Luis
  Last Name:   Chavez
  Username:    lchavez_meridian
  Email:       l.chavez@meridian-ind.com
  Password:    WellnessM2026!
  Role:        Member of gym (Default gym, ID 1)
  Screening results: BMI 33.4, BP 151/92, LDL 4.1 mmol/L

SECTION B — GROUP EXERCISE PROGRAM
Create the following workout routine (under admin account):

  Routine Name: "Meridian Ergonomic Wellness Circuit"
  Description: "12-week cardiovascular risk reduction program for sedentary manufacturing workers"

  Add these training days:

  Day 1: "Cardio and Core Activation"
    Day of week: Monday
    Exercises: Walking, Plank (search wger exercise database)

  Day 2: "Upper Body Resistance"
    Day of week: Wednesday
    Exercises: Dumbbell Lateral Raise, Push-up (search wger database)

  Day 3: "Lower Body Mobility and Strength"
    Day of week: Friday
    Exercises: Squats, Lunges (search wger exercise database)

Note: wger day-of-week codes — Monday=1, Tuesday=2, Wednesday=3,
      Thursday=4, Friday=5, Saturday=6, Sunday=7

SECTION C — GROUP NUTRITION PLAN
Create the following nutrition plan (under admin account):

  Plan Description: "Meridian Metabolic Risk Reduction Plan"
  Daily nutritional targets (based on AHA/ACC dietary guidelines):
    Energy:        2200 kcal
    Protein:        110 g
    Carbohydrates:  270 g
    Fat:             62 g

  Create the following meals within this plan:
    1. "Whole-Grain Breakfast"
    2. "Mid-Morning Snack"
    3. "Balanced Lunch"
    4. "Pre-Workout Snack"
    5. "Heart-Healthy Dinner"

SECTION D — MEASUREMENT TRACKING CATEGORIES
Create the following measurement categories (under admin account)
to track group progress at monthly check-ins:

  Category 1: "Waist Circumference"
    Unit: cm

  Category 2: "Resting Heart Rate"
    Unit: bpm

END OF ENROLLMENT BRIEF
DOCEOF

chown ga:ga /home/ga/Documents/occ_health_enrollment_brief.txt 2>/dev/null || true
echo "Enrollment brief written to /home/ga/Documents/occ_health_enrollment_brief.txt"

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
" 2>/dev/null > /tmp/corp_health_initial.json || echo '{"total_user_count":1,"routine_count":0,"measurement_category_count":0,"nutrition_plan_count":0}' > /tmp/corp_health_initial.json

echo "Baseline counts recorded:"
cat /tmp/corp_health_initial.json

# Record task start timestamp
date +%s > /tmp/corp_health_start_ts

# ---------------------------------------------------------------------------
# Launch Firefox to the wger dashboard
# ---------------------------------------------------------------------------
launch_firefox_to "http://localhost/en/dashboard" 5

take_screenshot /tmp/corp_health_start.png

echo "=== Task setup complete: corporate_health_screening_program ==="
