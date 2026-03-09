#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Tool Lending Tracker Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Generate CSV with realistic tool lending data using Python
# Use relative dates so task works regardless of when it's run
python3 << 'PYEOF'
from datetime import datetime, timedelta
import csv

# Calculate dates relative to today
today = datetime.now()

# Create tool lending data with various dates
tools_data = [
    ["Tool Name", "Borrower", "Date Lent", "Expected Return", "Value"],
    ["Power Drill", "John Smith", (today - timedelta(days=45)).strftime("%Y-%m-%d"), 
     (today - timedelta(days=35)).strftime("%Y-%m-%d"), "120"],
    ["Ladder", "Sarah Johnson", (today - timedelta(days=55)).strftime("%Y-%m-%d"), 
     (today - timedelta(days=48)).strftime("%Y-%m-%d"), "85"],
    ["Lawn Mower", "Mike Brown", (today - timedelta(days=15)).strftime("%Y-%m-%d"), 
     (today - timedelta(days=5)).strftime("%Y-%m-%d"), "350"],
    ["Chainsaw", "Emma Davis", (today - timedelta(days=62)).strftime("%Y-%m-%d"), 
     (today - timedelta(days=59)).strftime("%Y-%m-%d"), "200"],
    ["Socket Set", "Chris Wilson", (today - timedelta(days=8)).strftime("%Y-%m-%d"), 
     (today + timedelta(days=2)).strftime("%Y-%m-%d"), "75"],
    ["Pressure Washer", "Lisa Anderson", (today - timedelta(days=38)).strftime("%Y-%m-%d"), 
     (today - timedelta(days=31)).strftime("%Y-%m-%d"), "180"],
    ["Hedge Trimmer", "David Martinez", (today - timedelta(days=22)).strftime("%Y-%m-%d"), 
     (today - timedelta(days=12)).strftime("%Y-%m-%d"), "95"],
    ["Tile Saw", "Jennifer Taylor", (today - timedelta(days=70)).strftime("%Y-%m-%d"), 
     (today - timedelta(days=67)).strftime("%Y-%m-%d"), "250"],
]

# Write to CSV
with open('/home/ga/Documents/tool_lending.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerows(tools_data)

print("✅ Created tool_lending.csv with dynamic dates")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/tool_lending.csv
sudo chmod 666 /home/ga/Documents/tool_lending.csv

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc with tool lending data..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/tool_lending.csv > /tmp/calc_tool_lending.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_tool_lending.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
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

# Position cursor at A1
echo "Positioning cursor at cell A1..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Tool Lending Tracker Task Setup Complete ==="
echo "📝 Task Instructions:"
echo "  1. Add 'Days Out' column (E): Calculate days since tool was lent using =TODAY()-C2"
echo "  2. Add 'Status' column (F): Use =IF(E2>30,\"OVERDUE\",\"OK\") to flag overdue items"
echo "  3. Copy formulas down to all data rows"
echo "  4. Apply conditional formatting to Status column: Format → Conditional Formatting"
echo "  5. Set condition: Cell value = \"OVERDUE\", apply red background"
echo "💡 Tip: Tools out >30 days should show OVERDUE status"