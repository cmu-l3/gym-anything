#!/bin/bash
# setup_task.sh — Set up the reconcile_weight_unit_errors task
echo "=== Setting up reconcile_weight_unit_errors task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Wait for wger to be fully available
wait_for_wger_page

# -----------------------------------------------------------------------
# Inject the 5 "errors" (pounds instead of kilograms) into the existing 30-day data
# -----------------------------------------------------------------------
echo "Injecting weight unit errors into the database..."
cat > /tmp/seed_errors.py << 'EOF'
from django.contrib.auth.models import User
from wger.weight.models import WeightEntry

try:
    admin = User.objects.get(username='admin')
    # Get all entries, sorted by date descending
    entries = list(WeightEntry.objects.filter(user=admin).order_by('-date'))
    
    if len(entries) < 30:
        print(f"Warning: Only {len(entries)} entries found. Expected 30.")
        
    # Pick 5 consecutive days from roughly two weeks ago to convert to lbs
    for i in range(10, 15):
        if i < len(entries):
            entry = entries[i]
            # Convert existing kg value to lbs (1 kg = 2.2046 lbs)
            lbs_value = round(entry.weight * 2.2046, 1)
            entry.weight = lbs_value
            entry.save()
            print(f"Set outlier for {entry.date}: {lbs_value} lbs")
            
    print("Error injection complete.")
except Exception as e:
    import traceback
    print(f"Error seeding data: {e}")
    traceback.print_exc()
EOF

docker cp /tmp/seed_errors.py wger-web:/tmp/seed_errors.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/seed_errors.py').read())"

# Verify the outliers were created
ADMIN_ID=$(db_query "SELECT id FROM auth_user WHERE username='admin'")
INITIAL_OUTLIERS=$(db_query "SELECT COUNT(*) FROM weight_weightentry WHERE user_id=${ADMIN_ID} AND weight > 150" 2>/dev/null || echo "0")
echo "Initial outliers created: $INITIAL_OUTLIERS"
echo "$INITIAL_OUTLIERS" > /tmp/initial_outliers.txt

# -----------------------------------------------------------------------
# Launch Browser and Capture Initial State
# -----------------------------------------------------------------------
echo "Launching Firefox..."
launch_firefox_to "http://localhost/en/weight/overview/" 5

echo "Capturing initial state screenshot..."
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="