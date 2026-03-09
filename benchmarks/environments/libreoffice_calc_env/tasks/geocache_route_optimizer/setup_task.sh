#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Geocache Route Optimizer Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create geocache data CSV with realistic Rocky Mountain NP coordinates
cat > /home/ga/Documents/geocache_data.csv << 'EOF'
Cache Name,Latitude,Longitude,Difficulty,Terrain,Priority
Eagle's Nest,40.3428,-105.6836,3,4,1
Bear Lake View,40.3131,-105.6456,2,2,1
Alpine Meadow,40.3756,-105.7212,4,5,2
Waterfall Cache,40.3089,-105.6532,2,3,1
Summit Cache,40.3845,-105.7189,5,5,3
Pine Forest,40.3524,-105.6978,1,2,2
Hidden Valley,40.3678,-105.7145,3,3,2
Trailhead Cache,40.3198,-105.6623,1,1,1
Rock Scramble,40.3567,-105.7234,4,4,3
Lakeside Gem,40.3245,-105.6712,2,2,1
EOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/geocache_data.csv
sudo chmod 666 /home/ga/Documents/geocache_data.csv

echo "✅ Created geocache_data.csv with 10 caches"

# Create instruction sheet with starting coordinates
cat > /home/ga/Documents/geocache_instructions.txt << 'EOF'
GEOCACHE ROUTE OPTIMIZER TASK
==============================

SCENARIO:
You have 4 hours (240 minutes) before the park closes.
Plan which geocaches to find and in what order.

STARTING LOCATION:
Visitor Center: Latitude 40.3200, Longitude -105.6700

TASK REQUIREMENTS:
1. Calculate estimated time for each cache:
   Formula: 15 + (Difficulty-1)*5 + (Terrain-1)*8

2. Calculate distance from starting point (km):
   Simplified: 110 * SQRT((Lat - 40.3200)^2 + (Lon - (-105.6700))^2)
   Or more accurate with longitude correction

3. Calculate travel time (minutes):
   Formula: Distance_km * 2  (assuming 30 km/hour average)

4. Calculate total time per cache:
   Formula: Estimated_Time + Travel_Time

5. Select caches to include:
   - ALL Priority 1 caches MUST be included
   - Add Priority 2 if time permits
   - Add Priority 3 only if time still available

6. Verify total time ≤ 240 minutes

PRIORITY LEVELS:
Priority 1 = Must-find (5 caches)
Priority 2 = Want-to-find (3 caches)
Priority 3 = Nice-to-have (2 caches)

Good luck!
EOF

sudo chown ga:ga /home/ga/Documents/geocache_instructions.txt

echo "✅ Created instruction sheet"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/geocache_data.csv > /tmp/calc_geocache_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_geocache_task.log || true
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
        # Maximize window
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

# Move cursor to cell F1 to start working area (next to data columns)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
# Move to column F (A->B->C->D->E->F)
safe_xdotool ga :1 key Right Right Right Right Right
sleep 0.3

echo "=== Geocache Route Optimizer Task Setup Complete ==="
echo ""
echo "📋 TASK: Plan geocaching route within 240-minute time budget"
echo "📍 Starting location: Visitor Center (40.3200, -105.6700)"
echo "🎯 Objective: Include all Priority 1 caches + as many others as time permits"
echo ""
echo "💡 HINTS:"
echo "  1. Add column headers: Estimated Time, Distance (km), Travel Time, Total Time, Include?"
echo "  2. Calculate estimated time: =15 + (D2-1)*5 + (E2-1)*8"
echo "  3. Calculate distance: =110 * SQRT((B2-40.3200)^2 + (C2-(-105.6700))^2)"
echo "  4. Calculate travel time: =Distance * 2"
echo "  5. Calculate total time: =Estimated + Travel"
echo "  6. Mark 'YES' for Priority 1 caches (where Priority column = 1)"
echo "  7. Add Priority 2/3 if total time allows"
echo "  8. Sum total time: =SUMIF(Include_range, \"YES\", Total_time_range)"
echo "  9. Verify: Total ≤ 240 minutes"
echo ""
echo "📖 See /home/ga/Documents/geocache_instructions.txt for full details"