#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Water Leak Forensics Task ==="

# Create Documents directory if needed
sudo -u ga mkdir -p /home/ga/Documents

# Generate realistic water meter readings CSV with intentional messiness
# Days 1-21: Normal usage (~90 gal/day)
# Days 22-60: Leak present (~90 + 215 = 305 gal/day)

cat > /home/ga/Documents/water_meter_readings.csv << 'CSVEOF'
3/1/2024,12450.2
3/2/2024,12538.7
3/3/24,12628.1
3/4/24,12717.9
03/05/2024,12806.4
3/6/2024,12895.8
3/7/24,12986.2
3/8/24,13075.6
3/9/2024,13164.3
03/10/2024,13254.7
3/11/24,13343.2
3/12/24,13432.8
3/13/2024,13523.5
3/14/2024,13612.1
03/15/24,13702.6
3/16/24,13791.4
3/17/2024,13881.9
3/18/2024,13970.5
03/19/24,14060.8
3/20/24,14149.2
3/21/2024,14239.6
3/22/2024,14330.1
3/23/24,14635.7
3/24/24,14938.2
3/25/2024,15243.8
03/26/2024,15548.6
3/27/24,15854.1
3/28/24,16161.5
3/29/2024,16467.3
3/30/2024,16774.8
03/31/24,17081.2
4/1/24,17388.6
4/2/2024,17694.1
4/3/2024,18001.8
04/04/24,18308.2
4/5/24,18615.9
4/6/2024,18922.4
4/7/2024,19230.1
04/08/24,19536.8
4/9/24,19844.5
4/10/2024,20150.2
4/11/2024,20458.7
04/12/24,20765.3
4/13/24,21073.8
4/14/2024,21380.1
4/15/2024,21688.5
04/16/24,21994.2
4/17/24,22302.6
4/18/2024,22608.9
4/19/2024,22917.3
04/20/24,23223.1
4/21/24,23531.4
4/22/2024,23837.8
4/23/2024,24146.2
04/24/24,24452.7
4/25/24,24760.8
4/26/2024,25067.3
4/27/2024,25375.9
04/28/24,25682.4
4/29/24,25990.7
CSVEOF

chown ga:ga /home/ga/Documents/water_meter_readings.csv
chmod 644 /home/ga/Documents/water_meter_readings.csv

echo "✅ Created water_meter_readings.csv with 60 days of data"
echo "   - Days 1-21: Normal usage (~90 gal/day)"
echo "   - Days 22-60: Leak present (~305 gal/day)"
echo "   - Mixed date formats (intentional messiness)"

# Launch LibreOffice Calc (blank, agent will open the CSV)
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore > /tmp/calc_leak_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_leak_task.log || true
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

# Ensure cursor is at A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Water Leak Forensics Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "   Sarah received a water bill of \$487 instead of usual \$160."
echo "   She suspects a leak and has been recording daily meter readings."
echo "   The data is in: /home/ga/Documents/water_meter_readings.csv"
echo ""
echo "🎯 YOUR TASK:"
echo "   1. Open and import the CSV file"
echo "   2. Calculate daily water usage (difference between consecutive readings)"
echo "   3. Establish baseline from first ~20 days"
echo "   4. Identify when the leak started (when usage jumps significantly)"
echo "   5. Calculate total water wasted since leak started"
echo "   6. Calculate financial cost at \$0.0045 per gallon"
echo "   7. Create a summary report with findings"
echo "   8. Save as: /home/ga/Documents/results/water_leak_analysis.ods"
echo ""
echo "💡 HINTS:"
echo "   - Daily usage = Current reading - Previous reading"
echo "   - Baseline = Average of first 20 days"
echo "   - Leak = Days where usage > 150% of baseline"
echo "   - Waste per day = Daily usage - Baseline (if positive)"
echo "   - Use formulas (not manual calculations)"