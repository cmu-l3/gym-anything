#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Tool Library Overdue Tracker Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Calculate dates relative to today for realistic scenario
# We'll create dates using Python for proper date arithmetic
python3 << 'PYEOF'
from datetime import datetime, timedelta

today = datetime.now().date()

# Generate dates for various scenarios
dates = {
    'returned_recent': (today - timedelta(days=20), today - timedelta(days=13), today - timedelta(days=12)),  # Returned on time
    'overdue_urgent_1': (today - timedelta(days=25), today - timedelta(days=18), ''),  # 18 days overdue - URGENT
    'overdue_moderate': (today - timedelta(days=10), today - timedelta(days=3), ''),   # 3 days overdue
    'returned_late': (today - timedelta(days=15), today - timedelta(days=8), today - timedelta(days=6)),  # Returned (was late)
    'overdue_urgent_2': (today - timedelta(days=35), today - timedelta(days=28), ''),  # 28 days overdue - URGENT
    'overdue_just': (today - timedelta(days=8), today - timedelta(days=1), ''),        # 1 day overdue
    'ontime_1': (today - timedelta(days=5), today + timedelta(days=2), ''),            # Due in 2 days - On Time
    'returned_ontime': (today - timedelta(days=12), today - timedelta(days=5), today - timedelta(days=6)),  # Returned on time
    'overdue_urgent_3': (today - timedelta(days=30), today - timedelta(days=23), ''),  # 23 days overdue - URGENT
    'ontime_2': (today - timedelta(days=3), today + timedelta(days=4), ''),            # Due in 4 days - On Time
    'overdue_week': (today - timedelta(days=15), today - timedelta(days=8), ''),       # 8 days overdue - URGENT (just crossed threshold)
    'overdue_few': (today - timedelta(days=9), today - timedelta(days=2), ''),         # 2 days overdue
    'due_today': (today - timedelta(days=7), today, ''),                               # Due today (not yet overdue)
}

# Create CSV with tool library data
csv_content = '''Item Name,Borrower Name,Checkout Date,Due Date,Return Date
Power Drill,John Smith,{},{},{}
Chainsaw,William Thomas,{},{},{}
Circular Saw,David Lee,{},{},{}
Leaf Blower,Sarah Johnson,{},{},{}
Tile Saw,Robert Wilson,{},{},{}
Hedge Trimmer,Maria Garcia,{},{},{}
Paint Sprayer,Jennifer Taylor,{},{},{}
Extension Ladder,Lisa Anderson,{},{},{}
Pressure Washer,Mike Brown,{},{},{}
Lawn Mower,Emily Davis,{},{},{}
Post Hole Digger,James Martinez,{},{},{}
Wet/Dry Vacuum,Jessica Moore,{},{},{}
Electric Sander,Christopher White,{},{},{}'''.format(
    dates['returned_recent'][0], dates['returned_recent'][1], dates['returned_recent'][2],
    dates['overdue_urgent_1'][0], dates['overdue_urgent_1'][1], dates['overdue_urgent_1'][2],
    dates['overdue_moderate'][0], dates['overdue_moderate'][1], dates['overdue_moderate'][2],
    dates['returned_late'][0], dates['returned_late'][1], dates['returned_late'][2],
    dates['overdue_urgent_2'][0], dates['overdue_urgent_2'][1], dates['overdue_urgent_2'][2],
    dates['overdue_just'][0], dates['overdue_just'][1], dates['overdue_just'][2],
    dates['ontime_1'][0], dates['ontime_1'][1], dates['ontime_1'][2],
    dates['returned_ontime'][0], dates['returned_ontime'][1], dates['returned_ontime'][2],
    dates['overdue_urgent_3'][0], dates['overdue_urgent_3'][1], dates['overdue_urgent_3'][2],
    dates['ontime_2'][0], dates['ontime_2'][1], dates['ontime_2'][2],
    dates['overdue_week'][0], dates['overdue_week'][1], dates['overdue_week'][2],
    dates['overdue_few'][0], dates['overdue_few'][1], dates['overdue_few'][2],
    dates['due_today'][0], dates['due_today'][1], dates['due_today'][2]
)

with open('/home/ga/Documents/tool_library_data.csv', 'w') as f:
    f.write(csv_content)

print("✅ Created tool_library_data.csv with dynamic dates")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/tool_library_data.csv
sudo chmod 666 /home/ga/Documents/tool_library_data.csv

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/tool_library_data.csv > /tmp/calc_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_task.log || true
    # Don't exit, continue anyway
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit, continue anyway
fi

# Click on center of the screen to select current desktop (should be done in all tasks)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Calc window
echo "Focusing Calc window..."
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    if focus_window "$wid"; then
        # Maximize window
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

# Navigate to cell F1 to position for adding headers
echo "Positioning cursor..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
# Move to column F (5 right arrow presses from A)
safe_xdotool ga :1 key Right Right Right Right Right
sleep 0.2

echo "=== Tool Library Overdue Tracker Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "  1. Add header 'Days Overdue' in cell F1"
echo "  2. In F2, create formula: =IF(E2=\"\", MAX(0, TODAY()-D2), 0)"
echo "  3. Copy formula down to all data rows"
echo "  4. Add header 'Late Fee' in cell G1"
echo "  5. In G2, create formula: =IF(F2>0, F2*1, 0)"
echo "  6. Copy formula down to all data rows"
echo "  7. Add header 'Status' in cell H1"
echo "  8. In H2, create formula: =IF(E2<>\"\", \"Returned\", IF(F2>=7, \"URGENT\", IF(F2>0, \"Overdue\", \"On Time\")))"
echo "  9. Copy formula down to all data rows"
echo ""
echo "💡 Key concepts:"
echo "  - TODAY() returns current date"
echo "  - E2=\"\" checks if Return Date is empty"
echo "  - Date arithmetic: TODAY()-D2 gives days difference"
echo "  - Nested IF statements for multi-level logic"
echo ""