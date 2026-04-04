#!/bin/bash
# set -euo pipefail

echo "=== Setting up Appliance Failure Detective Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create messy dishwasher failure log CSV
cat > /home/ga/Documents/dishwasher_log.csv << 'CSVEOF'
Date,Cycle Type,Load Size,Water Temp,Drainage Success,Notes
3/15/2024,Normal,Medium,Warm,Yes,Clean drain
03/16/24,Heavy,Full,Hot,No,Water remained in bottom
3/17/2024,Quick,Light,Cold,Yes,
3-18-2024,Normal,Medium,Warm,Yes,
March 19 2024,Heavy,Full,Hot,No,Same issue - standing water
3/20/2024,Normal,Light,Warm,Yes,
3/21/24,Heavy,Medium,Hot,No,Drainage failure again
03-22-2024,Normal,Medium,Warm,Yes,
3/23/2024,Quick,Light,Cold,Yes,
March 24 2024,Normal,Full,Warm,No,First failure on Normal cycle
3/25/2024,Heavy,Full,Hot,No,Consistent on Heavy+Full+Hot
03/26/24,Quick,Light,Cold,Yes,
3-27-2024,Normal,Medium,Warm,Yes,
3/28/2024,Heavy,Full,Hot,No,Same pattern
3/29/24,Normal,Light,Warm,Yes,
March 30 2024,Quick,Medium,Cold,Yes,
3/31/2024,Normal,Medium,Warm,Yes,
04/01/24,Heavy,Full,Hot,No,Definitely a pattern
4-2-2024,Normal,Light,Cold,Yes,
April 3 2024,Quick,Light,Cold,Yes,
4/4/2024,Heavy,Medium,Hot,No,Heavy+Hot seems problematic
4/5/24,Normal,Medium,Warm,Yes,
04-06-2024,Normal,Full,Warm,Yes,
4/7/2024,Quick,Light,Cold,Yes,
April 8 2024,Heavy,Full,Hot,No,8th failure
4/9/2024,Normal,Medium,Warm,Yes,
4/10/24,Normal,Light,Cold,Yes,
4-11-2024,Heavy,Full,Hot,No,9th failure
April 12 2024,Quick,Medium,Cold,Yes,
4/13/2024,Normal,Medium,Warm,Yes,
04/14/24,Heavy,Medium,Hot,No,
4-15-2024,Normal,Light,Warm,Yes,
4/16/2024,Quick,Light,Cold,Yes,
April 17 2024,Heavy,Full,Hot,No,11th failure
4/18/2024,Normal,Medium,Warm,Yes,
4/19/24,Normal,Full,Warm,Yes,
04-20-2024,Quick,Light,Cold,Yes,
April 21 2024,Heavy,Full,Hot,No,12th failure - really consistent
4/22/2024,Normal,Medium,Warm,Yes,
4/23/24,Normal,Light,Cold,Yes,
4-24-2024,Heavy,Medium,Hot,Yes,Surprisingly worked
4/25/2024,Quick,Medium,Cold,Yes,
April 26 2024,Normal,Medium,Warm,Yes,
4/27/2024,Heavy,Full,Hot,No,13th failure
4/28/24,Normal,Light,Warm,Yes,
04-29-2024,Quick,Light,Cold,Yes,
April 30 2024,Normal,Medium,Warm,Yes,
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/dishwasher_log.csv
sudo chmod 644 /home/ga/Documents/dishwasher_log.csv

echo "✅ Created dishwasher_log.csv with 46 entries"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/dishwasher_log.csv > /tmp/calc_failure_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_failure_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
fi

# Click on center of the screen to select current desktop
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
        
        # Ensure cursor is at A1
        safe_xdotool ga :1 key ctrl+Home
        sleep 0.3
    fi
fi

echo "=== Appliance Failure Detective Task Setup Complete ==="
echo ""
echo "📊 TASK OBJECTIVE:"
echo "  Analyze dishwasher failure log to identify patterns for warranty claim"
echo ""
echo "📋 DATA LOADED:"
echo "  - 46 dishwasher run entries (March 15 - April 30, 2024)"
echo "  - Inconsistent date formats need cleaning"
echo "  - Mix of successful and failed drainage attempts"
echo ""
echo "✅ REQUIRED ANALYSIS:"
echo "  1. Standardize date formats and sort chronologically"
echo "  2. Calculate failure rates by Cycle Type (Normal/Heavy/Quick)"
echo "  3. Calculate failure rates by Load Size (Light/Medium/Full)"
echo "  4. Calculate failure rates by Water Temperature (Cold/Warm/Hot)"
echo "  5. Identify highest-risk condition"
echo "  6. Calculate days since first failure"
echo "  7. Apply percentage formatting and conditional formatting"
echo ""
echo "💡 HINT: Use COUNTIFS to count failures for each category"
echo "   Example: =COUNTIFS(\$B:\$B,\"Heavy\",\$E:\$E,\"No\")"