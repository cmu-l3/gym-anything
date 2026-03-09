#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Blood Donation Eligibility Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with messy blood donation history data
# Using mixed date formats to simulate real-world messiness
cat > /home/ga/Documents/blood_donation_history.csv << 'CSVEOF'
Date,Donation Type,Location,Notes
2023-08-15,Whole Blood,Red Cross Mobile,First donation this year
12/03/2023,Platelets,City Blood Center,
2024-01-22,Plasma,University Hospital,Felt great!
02/28/2024,Whole Blood,Red Cross Mobile,
2024-03-15,Platelets,City Blood Center,Regular donor
2024-04-10,Double Red Cells,Regional Center,New donation type
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/blood_donation_history.csv
sudo chmod 666 /home/ga/Documents/blood_donation_history.csv

echo "✅ Created blood donation history CSV with messy dates"
ls -lh /home/ga/Documents/blood_donation_history.csv

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc with blood donation data..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/blood_donation_history.csv > /tmp/calc_blood_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_blood_task.log || true
    # Don't exit, continue
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit, continue
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

# Move to cell A1 (top-left)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Blood Donation Eligibility Task Setup Complete ==="
echo ""
echo "📋 Task Instructions:"
echo "  1. Add column 'Days Since Donation' using DAYS(TODAY(), Date)"
echo "  2. Add column 'Waiting Period (Days)' with IF logic:"
echo "     - Whole Blood: 56 days"
echo "     - Platelets: 7 days"
echo "     - Plasma: 28 days"
echo "     - Double Red Cells: 112 days"
echo "  3. Add column 'Eligible?' (YES if Days Since >= Waiting Period)"
echo "  4. Add column 'Next Eligible Date' (Date + Waiting Period)"
echo "  5. Format date columns appropriately"
echo ""
echo "💡 Hint: Use nested IF statements for waiting periods by donation type"