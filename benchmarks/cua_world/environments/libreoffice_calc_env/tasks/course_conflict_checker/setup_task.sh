#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Course Conflict Checker Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with course data containing deliberate conflicts
cat > /home/ga/Documents/fall_2025_courses.csv << 'CSVEOF'
Course Code,Course Name,Days,Start Time,End Time,Credits,Selected
CS101,Intro to Programming,MWF,9:00 AM,9:50 AM,3,Yes
MATH201,Calculus II,MWF,9:30 AM,10:20 AM,4,Yes
PHYS101,Physics I + Lab,TTh,10:00 AM,11:50 AM,4,Yes
ENGL102,Composition II,MW,1:00 PM,2:15 PM,3,Yes
HIST150,World History,TTh,10:30 AM,11:45 AM,3,Yes
CS201,Data Structures,TTh,1:00 PM,2:15 PM,3,Yes
BIO101,Biology I,MWF,11:00 AM,11:50 AM,4,No
CHEM101,Chemistry I,TTh,2:30 PM,3:45 PM,4,No
PSYCH100,Intro Psychology,MW,3:00 PM,4:15 PM,3,No
ECON101,Microeconomics,F,2:00 PM,4:50 PM,3,No
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/fall_2025_courses.csv
sudo chmod 666 /home/ga/Documents/fall_2025_courses.csv

echo "✅ Created course schedule CSV with deliberate conflicts:"
echo "   - CS101 (MWF 9:00-9:50) vs MATH201 (MWF 9:30-10:20)"
echo "   - PHYS101 (TTh 10:00-11:50) vs HIST150 (TTh 10:30-11:45)"
echo "   - Total selected credits: 20 (OVERLOAD status)"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/fall_2025_courses.csv > /tmp/calc_conflict_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_conflict_task.log || true
    # Don't exit - let task continue
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit - let task continue
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

# Position cursor at cell A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Course Conflict Checker Task Setup Complete ==="
echo ""
echo "📋 TASK INSTRUCTIONS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Create a 'Time Conflicts' column (after column G)"
echo "2. Build formulas to detect courses with overlapping times"
echo "   - Check if days overlap (e.g., both have 'M')"
echo "   - Check if times overlap"
echo "3. Apply conditional formatting to highlight conflicts"
echo "4. Calculate total credits using SUM formula"
echo "5. Add enrollment status indicator:"
echo "   - FULL-TIME (≥12 credits)"
echo "   - PART-TIME (<12 credits)"
echo "   - OVERLOAD (>18 credits)"
echo ""
echo "💡 HINTS:"
echo "   - Known conflicts exist between:"
echo "     * CS101 and MATH201 (both MWF, overlapping times)"
echo "     * PHYS101 and HIST150 (both TTh, overlapping times)"
echo "   - Total selected credits should be 20 (3+4+4+3+3+3)"
echo "   - Use IF, AND, OR functions for conflict detection"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"