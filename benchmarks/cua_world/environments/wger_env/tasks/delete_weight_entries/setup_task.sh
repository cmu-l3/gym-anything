#!/bin/bash
set -e
echo "=== Setting up delete_weight_entries task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for wger to be ready
wait_for_wger_page

echo "Injecting body weight data into database..."

# Write python script to a temp file
cat > /tmp/wger_setup_weights.py << 'EOF'
import datetime
from django.contrib.auth.models import User
from wger.weight.models import WeightEntry

try:
    admin = User.objects.get(username='admin')
    today = datetime.date.today()

    # Ensure 30 valid entries exist (idempotent)
    for i in range(30):
        d = today - datetime.timedelta(days=30 - i)
        weight = round(87.0 - i * 0.15, 1)
        WeightEntry.objects.get_or_create(user=admin, date=d, defaults={'weight': weight})

    # Add 3 erroneous entries (values > 150kg)
    erroneous_entries = [
        (today - datetime.timedelta(days=35), 191.8),
        (today - datetime.timedelta(days=42), 190.5),
        (today - datetime.timedelta(days=49), 192.3),
    ]

    for d, w in erroneous_entries:
        obj, created = WeightEntry.objects.get_or_create(user=admin, date=d, defaults={'weight': w})
        if not created:
            obj.weight = w
            obj.save()

    print("Data injection successful.")
except Exception as e:
    print(f"Error during data injection: {e}")
EOF

# Copy script to container and execute it
docker cp /tmp/wger_setup_weights.py wger-web:/tmp/wger_setup_weights.py
docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/wger_setup_weights.py').read())"

# Query the database to get exact initial counts (Ground Truth)
ADMIN_ID=$(db_query "SELECT id FROM auth_user WHERE username='admin'" || echo "1")
INITIAL_TOTAL=$(db_query "SELECT COUNT(*) FROM weight_weightentry WHERE user_id=${ADMIN_ID}")
INITIAL_ERRONEOUS=$(db_query "SELECT COUNT(*) FROM weight_weightentry WHERE user_id=${ADMIN_ID} AND weight > 150")
INITIAL_CORRECT=$(db_query "SELECT COUNT(*) FROM weight_weightentry WHERE user_id=${ADMIN_ID} AND weight <= 150")

echo "Initial state recorded:"
echo "  Total entries:     $INITIAL_TOTAL"
echo "  Erroneous (>150):  $INITIAL_ERRONEOUS"
echo "  Correct (<=150):   $INITIAL_CORRECT"

# Save initial state safely for export script
cat > /tmp/initial_counts.json << EOF
{
    "initial_total": ${INITIAL_TOTAL:-0},
    "initial_erroneous": ${INITIAL_ERRONEOUS:-0},
    "initial_correct": ${INITIAL_CORRECT:-0}
}
EOF
chmod 666 /tmp/initial_counts.json

# Launch Firefox to the login page
launch_firefox_to "http://localhost/en/user/login" 5

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="