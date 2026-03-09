#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Medication Schedule Update Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Get current date for realistic timestamps
CURRENT_DATE=$(date +"%Y-%m-%d")
YESTERDAY_DATE=$(date -d "yesterday" +"%Y-%m-%d")

# Create CSV with medication schedule data
# Note: Times are set to create a realistic scenario
cat > /home/ga/Documents/medication_schedule.csv << EOF
Medication Name,Dosage,Frequency (hours),Last Dose Time,Next Dose
Lisinopril,10mg,12,$CURRENT_DATE 06:00:00,
Metformin,500mg,12,$CURRENT_DATE 07:00:00,
Atorvastatin,20mg,24,$YESTERDAY_DATE 20:00:00,
Aspirin,81mg,24,$YESTERDAY_DATE 18:00:00,
Gabapentin,300mg,8,$CURRENT_DATE 02:00:00,
EOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/medication_schedule.csv
sudo chmod 666 /home/ga/Documents/medication_schedule.csv

echo "✅ Created medication_schedule.csv with current date/time data"
cat /home/ga/Documents/medication_schedule.csv

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/medication_schedule.csv > /tmp/calc_medication_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_medication_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice" 90; then
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

echo "=== Medication Schedule Update Task Setup Complete ==="
echo ""
echo "📋 Task Instructions:"
echo "  1. Change Metformin (row 3) frequency from 12 to 8 hours"
echo "  2. Update Aspirin (row 5) last dose time to 8:00 AM today"
echo "  3. Add formulas in column E (Next Dose) to calculate: =D2+(C2/24)"
echo "  4. Copy formula down to all medication rows"
echo "  5. Apply conditional formatting to E2:E6 to highlight doses due within 2 hours"
echo ""
echo "💡 Hints:"
echo "  - Calc stores time as fractional days, so divide hours by 24"
echo "  - Formula for next dose: Last Dose Time + (Frequency / 24)"
echo "  - Conditional formatting: Format → Conditional → Condition"
echo "  - Use NOW() function to check if dose is due within 2 hours: E2<NOW()+(2/24)"