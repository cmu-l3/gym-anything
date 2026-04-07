#!/bin/bash
set -e
echo "=== Setting up Conditional Room Booking Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Calculate Dates
# We need "Friday of the upcoming week".
# Logic: Find next Monday, then add 4 days.
# Note: Odoo uses UTC for database storage, but the UI displays based on user timezone.
# We will assume naive datetime strings in setup are interpreted correctly by the environment setup.
PYTHON_SETUP_SCRIPT=$(cat << 'END_PYTHON'
from datetime import datetime, timedelta
import sys

# Calculate next Monday (same logic as environment setup)
now = datetime.now().replace(second=0, microsecond=0)
days_to_monday = (7 - now.weekday()) % 7 or 7
next_monday = now + timedelta(days=days_to_monday)
target_friday = next_monday + timedelta(days=4)

# Output for bash
print(target_friday.strftime('%Y-%m-%d'))
END_PYTHON
)

TARGET_DATE=$(python3 -c "$PYTHON_SETUP_SCRIPT")
echo "Target Date (Next Friday): $TARGET_DATE"

# 2. Randomize Scenario
# 0 = Free (Board Room)
# 1 = Blocked (Engineering Lab)
SCENARIO=$((RANDOM % 2))
# For debugging/forcing: SCENARIO=1

if [ "$SCENARIO" -eq 1 ]; then
    echo "Scenario: BLOCKED by 'Board Room Reserved'."
    EXPECTED_LOCATION="Engineering Lab"
    IS_BLOCKED="true"
    
    # Create the blocking event via XML-RPC
    python3 << PYTHON_EOF
import xmlrpc.client
import sys
url = '$ODOO_URL'
db = '$ODOO_DB'
pwd = '$ODOO_PASSWORD'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', pwd, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    # Create 'Board Room Reserved'
    # Start: Target Friday 14:00:00
    # Stop:  Target Friday 15:00:00
    start_dt = "$TARGET_DATE 14:00:00"
    stop_dt = "$TARGET_DATE 15:00:00"

    # Search if it already exists (idempotency)
    existing = models.execute_kw(db, uid, pwd, 'calendar.event', 'search',
        [[['name', '=', 'Board Room Reserved'], ['start', '=', start_dt]]])
        
    if not existing:
        models.execute_kw(db, uid, pwd, 'calendar.event', 'create', [{
            'name': 'Board Room Reserved',
            'start': start_dt,
            'stop': stop_dt,
            'location': 'Board Room',
            'description': 'Regular maintenance block',
            'allday': False
        }])
        print("Blocking event created.")
    else:
        print("Blocking event already exists.")
except Exception as e:
    print(f"Error creating event: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

else
    echo "Scenario: FREE slot."
    EXPECTED_LOCATION="Board Room"
    IS_BLOCKED="false"
    
    # Ensure no blocking event exists (cleanup)
    python3 << PYTHON_EOF
import xmlrpc.client
import sys
url = '$ODOO_URL'
db = '$ODOO_DB'
pwd = '$ODOO_PASSWORD'
try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
    uid = common.authenticate(db, 'admin', pwd, {})
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

    start_dt = "$TARGET_DATE 14:00:00"
    existing = models.execute_kw(db, uid, pwd, 'calendar.event', 'search',
        [[['name', '=', 'Board Room Reserved'], ['start', '=', start_dt]]])
        
    if existing:
        models.execute_kw(db, uid, pwd, 'calendar.event', 'unlink', [existing])
        print("Removed stale blocking event.")
except Exception as e:
    print(f"Error cleaning event: {e}", file=sys.stderr)
PYTHON_EOF
fi

# 3. Save Ground Truth for Export Script
# We save this to a temp file that export_result.sh will read
cat > /tmp/task_ground_truth.json << EOF
{
    "target_date": "$TARGET_DATE",
    "scenario_blocked": $IS_BLOCKED,
    "expected_location": "$EXPECTED_LOCATION"
}
EOF

chmod 644 /tmp/task_ground_truth.json
echo "Ground truth saved: $(cat /tmp/task_ground_truth.json)"

# 4. Prepare Browser
# Navigate to the weekly view (action_calendar_event)
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="