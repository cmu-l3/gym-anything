#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Accessible Venue Evaluator Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV file with messy, inconsistent venue data
cat > /home/ga/Documents/venues_raw_data.csv << 'CSVEOF'
Venue,Event,Date,Entry Description,Parking Notes,Restroom,Hearing Support,Parking Cost,Companion Required,Equipment Rental,Event Importance
Grand Ballroom,Best Friend Wedding,2024-06-15,3 steps at main entrance but ramp available around back,Accessible parking available - $15 fee,Single accessible stall on main floor,No hearing loop system - loud music environment,15,No,0,10
Tech Conference Center,Industry Conference,2024-07-22,Level entry from parking lot,Free accessible parking spaces near entrance,Multiple accessible restrooms throughout,Live captioning provided on screens,0,No,0,7
Vintage Theater,Jazz Concert,2024-08-10,Historical building - 5 steps at entrance with no ramp option,Street parking only - no designated accessible spaces,Restroom on second floor - no elevator access,No hearing assistance available,25,Yes,0,6
Community Center,Family Reunion,2024-08-28,ADA compliant building - level entry with automatic doors,Accessible parking available in front lot,Accessible restroom with grab bars,Hearing loop system installed,10,No,25,9
Arena Stadium,Rock Concert,2024-09-14,Ramped entrance to accessible seating section,Accessible parking $30 - located far from entrance,Accessible facilities available,Assistive listening devices for rent,30,No,15,4
Learning Hub,Photography Workshop,2024-09-20,Ground level access - automatic doors throughout,Free parking with designated accessible spaces,Fully accessible restroom facilities,Real-time captions displayed on screens,0,No,0,5
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/venues_raw_data.csv
sudo chmod 644 /home/ga/Documents/venues_raw_data.csv

echo "✅ Created venues_raw_data.csv with 6 venues"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/venues_raw_data.csv > /tmp/calc_venue_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_venue_task.log
    # Don't exit, continue anyway
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice" 90; then
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
        
        # Move to cell A1
        safe_xdotool ga :1 key ctrl+Home
        sleep 0.3
    fi
fi

echo "=== Accessible Venue Evaluator Task Setup Complete ==="
echo ""
echo "📋 TASK OVERVIEW:"
echo "   Maya needs help evaluating 6 venues for accessibility and cost"
echo ""
echo "🎯 YOUR MISSION:"
echo "   1. CREATE standardization columns (Level/Ramped Entry?, Accessible Restroom?, etc.)"
echo "   2. USE IF/OR/SEARCH formulas to parse text into Yes/No flags"
echo "   3. CALCULATE Total Access Cost (parking + companion + equipment)"
echo "   4. IDENTIFY venues meeting ALL minimum requirements (AND logic)"
echo "   5. CREATE Cost-Effectiveness Score (Importance / Cost)"
echo "   6. SAVE as accessible_venues_evaluated.ods"
echo ""
echo "💡 HINTS:"
echo "   - Entry Description: look for 'level', 'ramp' = Yes | 'steps', 'stairs' = No"
echo "   - Companion tickets cost $50 when required"
echo "   - Min requirements: Level Entry AND Accessible Restroom AND Hearing Support"
echo "   - Formula example: =IF(OR(ISNUMBER(SEARCH(\"level\",D2)),ISNUMBER(SEARCH(\"ramp\",D2))),\"Yes\",\"No\")"
echo ""
echo "📊 Raw data loaded with inconsistent accessibility information - time to clean it!"