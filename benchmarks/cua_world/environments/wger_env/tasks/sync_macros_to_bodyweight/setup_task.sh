#!/bin/bash
echo "=== Setting up sync_macros_to_bodyweight task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for wger to be responsive
wait_for_wger_page

# Generate a random weight between 80.0 and 89.9 kg
# This prevents the agent from hardcoding the answer and forces information retrieval
RAND_VAL=$(( RANDOM % 100 ))
WEIGHT=$(awk -v r=$RAND_VAL 'BEGIN {printf "%.1f", 80.0 + r/10.0}')

echo "Injected random body weight for today: $WEIGHT kg"

# Configure the database to the exact starting state
echo "Setting up database state..."
cat > /tmp/setup_state.py << EOF
import datetime
from django.contrib.auth.models import User
from wger.weight.models import WeightEntry
from wger.nutrition.models import NutritionPlan

try:
    admin = User.objects.get(username='admin')
    today = datetime.date.today()

    # Clear today's weights and add the exact random one
    WeightEntry.objects.filter(user=admin, date=today).delete()
    WeightEntry.objects.create(user=admin, date=today, weight=$WEIGHT)

    # Ensure Lean Bulk Plan exists and goals are zeroed
    plan, _ = NutritionPlan.objects.get_or_create(user=admin, description='Lean Bulk Plan')
    plan.goal_energy = 0
    plan.goal_protein = 0
    plan.goal_carbohydrates = 0
    plan.goal_fat = 0
    plan.goal_fiber = 0
    plan.save()
    
    print("State setup successful")
except Exception as e:
    print(f"Error setting up state: {e}")
EOF

docker cp /tmp/setup_state.py wger-web:/tmp/setup_state.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/setup_state.py').read())"

# Launch Firefox to the dashboard
launch_firefox_to "http://localhost/en/dashboard/" 5

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="