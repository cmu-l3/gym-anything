#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Mileage Tax Deduction Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create incomplete mileage log CSV
cat > /home/ga/Documents/mileage_log.csv << 'CSVEOF'
Date,Start Odo,End Odo,Distance,Purpose,Business Miles,Rate,Deduction
2023-01-15,45230,45267,,Client meeting - downtown,,,
2023-01-18,45267,45301,34,Personal - grocery shopping,0,0.655,
2023-01-22,45301,45389,,Site visit - Johnson project,,,
2023-01-25,45389,45405,16,Personal - doctor appointment,0,0.655,
2023-02-03,45405,45492,,Conference attendance,,,
2023-02-10,45492,45518,26,Personal - family visit,0,0.655,
2023-02-14,45518,45561,,Client meeting - Smith Corp,,,
2023-02-20,45561,45595,34,Personal - weekend trip,0,0.655,
2023-03-05,45595,45678,,Training workshop - certification,,,
2023-03-12,45678,45703,25,Personal - shopping,0,0.655,
TOTALS,,,,,,,
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/mileage_log.csv
sudo chmod 666 /home/ga/Documents/mileage_log.csv

echo "✅ Created incomplete mileage log CSV"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/mileage_log.csv > /tmp/calc_mileage_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_mileage_task.log || true
    # Don't exit, continue for robustness
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit, continue for robustness
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

# Position cursor at cell D2 (first missing distance calculation)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
# Move to D2: Right 3 times, Down once
safe_xdotool ga :1 key Right Right Right Down
sleep 0.2

echo "=== Mileage Tax Deduction Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Calculate missing distances: =C#-B# (e.g., =C2-B2)"
echo "  2. Copy Distance to Business Miles for business trips"
echo "  3. Enter 0 for personal trips in Business Miles (if not already)"
echo "  4. Fill Rate column with 0.655 for business trips"
echo "  5. Calculate deductions: =F#*G# (e.g., =F2*G2)"
echo "  6. Add SUM formulas in TOTALS row for Business Miles and Deduction"
echo "  7. Format Deduction column as currency"
echo ""
echo "💡 Business trips contain: Client, Meeting, Site, Conference, Training, Workshop"
echo "💡 IRS Standard Mileage Rate 2023: $0.655 per mile"