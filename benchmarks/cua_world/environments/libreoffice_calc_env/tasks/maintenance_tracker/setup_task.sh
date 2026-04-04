#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Maintenance Tracker Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Generate maintenance request data with realistic dates
# Use Python to create CSV with dates spanning past 30 days
python3 << 'PYEOF'
import csv
from datetime import datetime, timedelta
import random

# Calculate dates spanning past 30 days
today = datetime.now()
base_date = today - timedelta(days=30)

issues = [
    "Kitchen sink dripping",
    "Toilet won't flush properly",
    "No hot water in bathroom",
    "Refrigerator not cooling",
    "Broken window screen",
    "Leaky faucet in bathroom",
    "HVAC making loud noise",
    "Dishwasher not draining",
    "Garbage disposal jammed",
    "Loose cabinet door",
    "Cracked bathroom tile",
    "Bedroom door won't close",
    "Smoke detector beeping",
    "Light fixture flickering",
    "Thermostat not working",
    "Clogged shower drain",
    "Broken blinds in living room",
    "Ceiling stain from leak",
    "Outlet not working"
]

statuses = ["Open", "In Progress", "Completed"]
status_weights = [0.4, 0.3, 0.3]  # 40% Open, 30% In Progress, 30% Completed

staff = ["Mike P.", "Sarah L.", "Tom R.", ""]
costs = [0, 75, 95, 120, 150, 180, 200, 250, 275, 350, 425]

# Generate 18 maintenance requests
requests = []
units = list(range(101, 113))  # Units 101-112

for i in range(18):
    # Random date within past 30 days
    days_ago = random.randint(1, 30)
    request_date = today - timedelta(days=days_ago)
    
    status = random.choices(statuses, weights=status_weights)[0]
    issue = random.choice(issues)
    unit = random.choice(units)
    
    # Assign staff and cost based on status
    if status == "Open":
        assigned = ""
        cost = 0
    elif status == "In Progress":
        assigned = random.choice([s for s in staff if s])
        cost = random.choice(costs[1:6])  # Lower costs for in-progress
    else:  # Completed
        assigned = random.choice([s for s in staff if s])
        cost = random.choice(costs[1:])  # Any cost
    
    requests.append({
        'date': request_date.strftime('%Y-%m-%d'),
        'unit': unit,
        'issue': issue,
        'status': status,
        'assigned': assigned,
        'cost': cost
    })

# Sort by date (oldest first)
requests.sort(key=lambda x: x['date'])

# Write to CSV
with open('/home/ga/Documents/maintenance_log.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['Request Date', 'Unit #', 'Issue Description', 'Status', 'Assigned To', 'Cost', 'Days Open'])
    
    for req in requests:
        writer.writerow([
            req['date'],
            req['unit'],
            req['issue'],
            req['status'],
            req['assigned'],
            f"${req['cost']}" if req['cost'] > 0 else "$0",
            ""  # Days Open column is empty - agent must add formulas
        ])

print(f"Created maintenance log with {len(requests)} requests")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/maintenance_log.csv
sudo chmod 666 /home/ga/Documents/maintenance_log.csv

echo "✅ Created maintenance_log.csv with realistic request data"
ls -lh /home/ga/Documents/maintenance_log.csv

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/maintenance_log.csv > /tmp/calc_maintenance_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_maintenance_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
fi

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Calc window
echo "Focusing Calc window..."
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    if focus_window "$wid"; then
        echo "✅ Calc window focused"
        # Maximize window
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

# Position cursor at G2 (first Days Open data cell) to hint at starting point
echo "Positioning cursor at Days Open column..."
safe_xdotool ga :1 key ctrl+Home  # Go to A1
sleep 0.3
safe_xdotool ga :1 key Right Right Right Right Right Right  # Move to G1
sleep 0.2
safe_xdotool ga :1 key Down  # Move to G2
sleep 0.2

echo "=== Maintenance Tracker Task Setup Complete ==="
echo ""
echo "📋 SCENARIO: You're a property manager. Tenant is threatening to withhold"
echo "   rent over an 'ignored' repair. Your boss needs a proper tracking system TODAY."
echo ""
echo "📝 YOUR TASKS:"
echo "  1. Add formulas in 'Days Open' column (G): =TODAY()-A2 (copy down)"
echo "  2. Highlight overdue items: Conditional format Days Open >7 in RED"
echo "  3. Color-code Status column: Open=Yellow, In Progress=Blue, Completed=Green"
echo "  4. Create summary section below data with:"
echo "     - Total Requests: =COUNTA(A2:A20)"
echo "     - Open/In Progress: =COUNTIF(D2:D20,\"Open\")+COUNTIF(D2:D20,\"In Progress\")"
echo "     - Overdue (>7 days, not completed): =COUNTIFS(D2:D20,\"<>Completed\",G2:G20,\">7\")"
echo "     - Total Costs: =SUM(F2:F20)"
echo "  5. Format summary section (bold labels, borders)"
echo ""
echo "💡 HINT: Cursor is positioned at G2 (Days Open column) to get you started!"