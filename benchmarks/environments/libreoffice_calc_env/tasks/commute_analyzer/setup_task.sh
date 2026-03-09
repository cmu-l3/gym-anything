#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Commute Route Analyzer Task ==="

# Create Documents directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV file with commute data
# Note: Some cells intentionally empty (worked from home those days)
cat > /home/ga/Documents/commute_data.csv << 'EOF'
Day,Highway (minutes),Scenic Route (minutes),City Streets (minutes)
Monday Week 1,25,34,28
Tuesday Week 1,32,36,45
Wednesday Week 1,27,33,31
Thursday Week 1,,35,29
Friday Week 1,38,37,42
Monday Week 2,24,35,26
Tuesday Week 2,45,38,
Wednesday Week 2,26,34,30
Thursday Week 2,29,36,35
Friday Week 2,31,37,39
EOF

# Set proper ownership
sudo chown ga:ga /home/ga/Documents/commute_data.csv
sudo chmod 666 /home/ga/Documents/commute_data.csv

echo "✅ Created commute_data.csv with 10 days of data"

# Create a text file with additional context information
cat > /home/ga/Documents/route_info.txt << 'INFOEOF'
Route Information for Cost Calculation:

Highway Route:
- Distance: 18 miles each way
- Toll: $3.50 each way
- Weekly toll cost: $3.50 × 2 trips/day × 5 days = $35
- Estimated weekly gas: $27
- Total weekly cost: $62

Scenic Route:
- Distance: 22 miles each way
- No tolls
- Estimated weekly gas: $33
- Total weekly cost: $33

City Streets:
- Distance: 16 miles each way
- No tolls
- Estimated weekly gas: $24
- Total weekly cost: $24

TASK: Calculate average time, reliability (standard deviation), and weekly cost for each route.
Recommend which route is best overall.
INFOEOF

sudo chown ga:ga /home/ga/Documents/route_info.txt

echo "✅ Created route_info.txt with cost details"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/commute_data.csv > /tmp/calc_commute_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_commute_task.log || true
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

# Move cursor to cell A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Commute Route Analyzer Task Setup Complete ==="
echo ""
echo "📊 Task Context:"
echo "   You're analyzing 3 commute routes to a new job"
echo "   Data: 10 days of actual drive times (some days missing)"
echo ""
echo "📝 Required Analysis:"
echo "   1. Calculate AVERAGE time for each route (3 formulas)"
echo "   2. Calculate STDEV for reliability (3 formulas)"
echo "   3. Calculate weekly costs (tolls + gas)"
echo "   4. Create summary comparison table"
echo "   5. Highlight/mark your recommended route"
echo ""
echo "💡 Key Info:"
echo "   - Highway: $3.50 toll each way ($35/week + $27 gas)"
echo "   - Scenic: No tolls ($33/week gas)"
echo "   - City: No tolls ($24/week gas)"
echo ""
echo "🎯 Goal: Find best balance of time, reliability, and cost"
echo ""
echo "📄 Reference: Check /home/ga/Documents/route_info.txt for details"