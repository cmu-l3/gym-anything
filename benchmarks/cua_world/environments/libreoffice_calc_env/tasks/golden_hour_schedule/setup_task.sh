#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Golden Hour Photography Schedule Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with scrambled location data
# Note: Data is intentionally NOT sorted by optimal time
cat > /home/ga/Documents/photo_locations.csv << 'EOF'
Location Name,Address,Optimal Start Time,Travel Time (min),Setup Time (min)
Riverside Park,234 River Rd,18:15,12,5
Downtown Bridge,89 Main St,17:45,8,5
Hilltop Overlook,456 Summit Ave,18:30,15,5
Lakefront Pier,12 Lake Dr,17:30,20,5
Garden District,567 Maple St,18:00,10,5
EOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/photo_locations.csv
sudo chmod 666 /home/ga/Documents/photo_locations.csv

echo "✅ Created photo_locations.csv with scrambled data"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/photo_locations.csv > /tmp/calc_schedule_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_schedule_task.log || true
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

# Move cursor to cell A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Golden Hour Photography Schedule Task Setup Complete ==="
echo "📸 Photography Shoot Scheduler"
echo ""
echo "📋 Task Instructions:"
echo "  1. Sort locations by 'Optimal Start Time' column (ascending)"
echo "     - Select entire data range (A1:E6)"
echo "     - Use Data → Sort"
echo "  2. Add new column 'Arrival Time' in column F"
echo "  3. For first location (row 2): Arrival = Optimal Start Time"
echo "  4. For other locations: Arrival = Previous Arrival + Previous Setup + Previous Travel"
echo "  5. Use formulas (not hardcoded times)"
echo ""
echo "💡 Formula hints:"
echo "  - F2: =C2  (first location arrives at optimal time)"
echo "  - F3: =F2+TIME(0,E2+D2,0)  (add setup + travel time)"
echo "  - Copy formula down for remaining locations"
echo ""
echo "🎯 Goal: Create an optimized schedule where you arrive at each location"
echo "   during its optimal golden hour lighting window"