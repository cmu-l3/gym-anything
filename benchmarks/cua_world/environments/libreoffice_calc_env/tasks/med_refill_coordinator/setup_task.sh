#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Medication Refill Coordinator Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with medication data
# Use dates that will create realistic scenarios
# Dates are set to create a mix of urgent and non-urgent medications
cat > /home/ga/Documents/medications.csv << 'EOF'
Medication Name,Last Refill Date,Quantity Dispensed,Daily Dosage,Pharmacy Name
Lisinopril 10mg,2024-03-15,30,1,CVS Pharmacy
Metformin 500mg,2024-03-01,180,2,Walgreens
Atorvastatin 20mg,2024-03-20,90,1,Rite Aid
Levothyroxine 50mcg,2024-02-28,90,1,Walgreens
Omeprazole 20mg,2024-03-25,60,1,CVS Pharmacy
EOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/medications.csv
sudo chmod 666 /home/ga/Documents/medications.csv

echo "✅ Created medications.csv with sample data"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc with medications.csv..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/medications.csv > /tmp/calc_med_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_med_task.log || true
    # Don't exit, continue anyway
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit, continue anyway
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

# Move to cell A1 to ensure starting position
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Medication Refill Coordinator Task Setup Complete ==="
echo ""
echo "📋 Current data:"
echo "  • 5 medications with different refill schedules"
echo "  • Columns: Name, Last Refill Date, Quantity, Daily Dosage, Pharmacy"
echo ""
echo "📝 Required actions:"
echo "  1. Add column F: Days Supply = Quantity ÷ Daily Dosage"
echo "  2. Add column G: Refill Due Date = Last Refill + Days Supply"
echo "  3. Add column H: Insurance Allows Refill = Last Refill + (Days Supply × 0.75)"
echo "  4. Add column I: Days Until Can Refill = Insurance Date - TODAY()"
echo "  5. Add column J: Days Until Out = Refill Due - TODAY()"
echo "  6. Add column K: ACTION NEEDED with IF logic for urgency"
echo "  7. Apply conditional formatting (Red=URGENT, Yellow=This Week)"
echo "  8. Sort by Days Until Out (ascending, most urgent first)"
echo ""
echo "💡 Tip: Create formulas in row 2 first, then copy down to other rows"