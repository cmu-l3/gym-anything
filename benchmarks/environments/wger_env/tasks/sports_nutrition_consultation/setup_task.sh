#!/bin/bash
# Task setup: sports_nutrition_consultation
# Cleans up stale artifacts, writes the consultation document,
# records baselines, and launches Firefox to the wger dashboard.

source /workspace/scripts/task_utils.sh

chmod +x /workspace/tasks/sports_nutrition_consultation/export_result.sh

echo "=== Setting up sports_nutrition_consultation task ==="

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
target_dates = ['2026-01-05','2026-01-12','2026-01-19','2026-01-26',
                '2026-02-02','2026-02-09','2026-02-16','2026-02-23']
for d in target_dates:
    WeightEntry.objects.filter(user=admin, date=d).delete()
print('Weight entries cleaned')
" 2>/dev/null || true

docker exec wger-web python3 manage.py shell -c "
from wger.nutrition.models import NutritionPlan
for desc in ['Powerlifter Off-Season Hypertrophy Phase', 'Powerlifter Competition Peak - Weight Cut']:
    deleted = NutritionPlan.objects.filter(description=desc, user__username='admin').delete()
    print(f'Deleted nutrition plan {desc}: {deleted}')
" 2>/dev/null || true

docker exec wger-web python3 manage.py shell -c "
from wger.measurement.models import Category
for name in ['Body Fat Percentage', 'Lean Body Mass', 'Vertical Jump Height']:
    deleted = Category.objects.filter(name=name, user__username='admin').delete()
    print(f'Deleted measurement category {name}: {deleted}')
" 2>/dev/null || true

sleep 1

# ---------------------------------------------------------------------------
# Write the companion consultation document
# ---------------------------------------------------------------------------
mkdir -p /home/ga/Documents

cat > /home/ga/Documents/sports_nutrition_consult.txt << 'DOCEOF'
PERFORMANCE NUTRITION ASSOCIATES
REGISTERED SPORTS DIETITIAN — CONSULTATION RECORD
===================================================
Client: Elite Powerlifter (tracked under admin account)
Division: 105 kg, Open Category
Competition: National Powerlifting Championships (April 2026)
RD-CSSD: You (logged in as admin)
Consultation Date: 2026-03-07
===================================================

SECTION A — CLIENT BODY WEIGHT HISTORY
Log the following weekly weigh-ins (kg) recorded since program start:

  Date          Weight (kg)
  2026-01-05    104.2
  2026-01-12    104.8
  2026-01-19    105.3
  2026-01-26    105.6
  2026-02-02    106.1
  2026-02-09    106.4
  2026-02-16    105.8
  2026-02-23    104.9

SECTION B — BODY COMPOSITION MEASUREMENT HISTORY
Create the following measurement categories and enter all historical data:

CATEGORY 1: "Body Fat Percentage"
  Unit: %
  Assessment history (monthly DEXA scans):
    2026-01-08    18.4
    2026-02-05    17.9
    2026-03-05    17.2

CATEGORY 2: "Lean Body Mass"
  Unit: kg
  Assessment history (from same DEXA scans):
    2026-01-08    85.1
    2026-02-05    86.3
    2026-03-05    87.8

CATEGORY 3: "Vertical Jump Height"
  Unit: cm
  Assessment history (monthly force plate testing):
    2026-01-08    58
    2026-02-05    61
    2026-03-05    64

SECTION C — PERIODIZED NUTRITION PLANS

Create BOTH of the following nutrition plans in wger:

==== PLAN 1: OFF-SEASON BUILDING PHASE ====

  Plan Description: "Powerlifter Off-Season Hypertrophy Phase"
  Daily Macro Targets:
    Energy:         4200 kcal
    Protein:         230 g
    Carbohydrates:   520 g
    Fat:             110 g

  Create the following meals within this plan (in this order):
    1. "Pre-Workout Fuel"
    2. "Post-Workout Recovery"
    3. "Breakfast"
    4. "Lunch"
    5. "Dinner"
    6. "Evening Snack"

==== PLAN 2: COMPETITION PEAK — WEIGHT CUT ====

  Plan Description: "Powerlifter Competition Peak - Weight Cut"
  Daily Macro Targets:
    Energy:         2800 kcal
    Protein:         260 g
    Carbohydrates:   280 g
    Fat:              70 g

  Create the following meals within this plan (in this order):
    1. "Morning Weigh-In Breakfast"
    2. "Pre-Attempt Snack"
    3. "Inter-Attempt Fuel"
    4. "Post-Competition Recovery"

IMPORTANT: Both nutrition plans must have their daily goal values set
(Energy, Protein, Carbohydrates, Fat) AND have the meals listed above
created within each respective plan.

END OF CONSULTATION RECORD
DOCEOF

chown ga:ga /home/ga/Documents/sports_nutrition_consult.txt 2>/dev/null || true
echo "Consultation document written to /home/ga/Documents/sports_nutrition_consult.txt"

# ---------------------------------------------------------------------------
# Record initial baseline counts
# ---------------------------------------------------------------------------
docker exec wger-web python3 manage.py shell -c "
import json
from django.contrib.auth.models import User
from wger.weight.models import WeightEntry
from wger.measurement.models import Category as MeasureCategory
from wger.nutrition.models import NutritionPlan

admin = User.objects.get(username='admin')
baselines = {
    'weight_entry_count': WeightEntry.objects.filter(user=admin).count(),
    'measurement_category_count': MeasureCategory.objects.filter(user=admin).count(),
    'nutrition_plan_count': NutritionPlan.objects.filter(user=admin).count()
}
print(json.dumps(baselines))
" 2>/dev/null > /tmp/sports_nutrition_initial.json || echo '{"weight_entry_count":0,"measurement_category_count":0,"nutrition_plan_count":0}' > /tmp/sports_nutrition_initial.json

echo "Baseline counts recorded:"
cat /tmp/sports_nutrition_initial.json

# Record task start timestamp
date +%s > /tmp/sports_nutrition_start_ts

# ---------------------------------------------------------------------------
# Launch Firefox to the wger dashboard
# ---------------------------------------------------------------------------
launch_firefox_to "http://localhost/en/dashboard" 5

take_screenshot /tmp/sports_nutrition_start.png

echo "=== Task setup complete: sports_nutrition_consultation ==="
