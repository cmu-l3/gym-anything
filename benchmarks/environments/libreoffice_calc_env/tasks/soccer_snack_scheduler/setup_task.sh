#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Soccer Snack Scheduler Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create messy CSV file with intentional issues
cat > /home/ga/Documents/messy_snack_schedule.csv << 'EOF'
Date,Family,Allergen Awareness,Notes
10/13/2024,Smith,No,
09/15/2024,Anderson,No,
12/15/2024,Michael,No,First name only
09/22/2024,Smith Family,Yes - Nut Allergy,DUPLICATE!
11/17/2024,Wilson,No,
10/06/2024,Williams Family,Yes - Nut Allergy,
09/29/2024,Johnson,No,
11/03/2024,davis,No,Lowercase
10/20/2024,Brown,No,
12/08/2024,Martinez Family,Yes - Nut Allergy,
11/10/2024,Miller Family,No,
01/05/2025,Taylor,No,
12/01/2024,Thomas Family,No,
10/27/2024,Jones,Yes - Nut Allergy,
EOF

# Set permissions
sudo chown ga:ga /home/ga/Documents/messy_snack_schedule.csv
sudo chmod 666 /home/ga/Documents/messy_snack_schedule.csv

echo "✅ Created messy_snack_schedule.csv with intentional issues:"
echo "   - Inconsistent name formats"
echo "   - Smith Family appears twice, Garcia Family missing"
echo "   - Dates out of chronological order"
echo "   - Allergen info not highlighted"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/messy_snack_schedule.csv > /tmp/calc_snack_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_snack_task.log || true
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

# Move cursor to home position
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Soccer Snack Scheduler Task Setup Complete ==="
echo ""
echo "🏈 SCENARIO: You've inherited this messy snack schedule!"
echo "📋 PROBLEMS TO FIX:"
echo "   1. Inconsistent family name formats"
echo "   2. Smith Family assigned twice, Garcia Family not assigned"
echo "   3. Dates are out of chronological order"
echo "   4. Allergen information not visually highlighted"
echo "   5. No cost estimates or fairness tracking"
echo ""
echo "✅ YOUR TASKS:"
echo "   1. Standardize all family names to consistent format"
echo "   2. Sort by date chronologically"
echo "   3. Fix duplicates - reassign Smith's 2nd slot to Garcia Family"
echo "   4. Add 'Est. Cost Per Week' column (\$25 each)"
echo "   5. Apply conditional formatting to highlight allergen weeks"
echo "   6. Add fairness check (count assignments per family)"
echo "   7. Calculate total season cost"
echo "   8. Format for professional appearance"
echo ""
echo "⏰ Parents need this by tonight!"