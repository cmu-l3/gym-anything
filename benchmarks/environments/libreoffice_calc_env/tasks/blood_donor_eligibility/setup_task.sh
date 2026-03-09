#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Blood Donor Eligibility Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Generate blood donor database with realistic data
# Mix of dates: some eligible (>56 days ago), some not (<56 days ago)
cat > /home/ga/Documents/blood_donors.csv << 'EOF'
Donor Name,Blood Type,Last Donation Date,Phone Number
Maria Garcia,O+,2024-09-15,555-0101
James Chen,A+,2024-11-20,555-0102
Sarah Johnson,O+,2024-08-30,555-0103
Michael Brown,B+,2024-10-15,555-0104
Emily Davis,O-,2024-09-25,555-0105
David Wilson,AB+,2024-11-01,555-0106
Lisa Anderson,A-,2024-08-20,555-0107
Robert Taylor,O+,2024-11-25,555-0108
Jennifer Martinez,B-,2024-10-05,555-0109
William Thomas,O+,2024-09-10,555-0110
Jessica Moore,A+,2024-11-15,555-0111
Christopher Lee,AB-,2024-08-15,555-0112
Amanda White,O+,,555-0113
Matthew Harris,B+,2024-10-25,555-0114
Ashley Clark,O-,2024-09-05,555-0115
Daniel Lewis,A+,2024-11-10,555-0116
Stephanie Walker,O+,2024-08-25,555-0117
Joshua Hall,B-,,555-0118
EOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/blood_donors.csv
sudo chmod 666 /home/ga/Documents/blood_donors.csv

echo "✅ Created blood donor database: blood_donors.csv"
echo "   - 18 donors with varying blood types"
echo "   - Last donation dates range from 30-120 days ago"
echo "   - 2 donors with missing last donation dates"
echo "   - Urgent need: O+ blood type"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc with donor database..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/blood_donors.csv > /tmp/calc_donor_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_donor_task.log || true
    # Continue anyway - verifier will catch if task failed
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Continue anyway
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

# Ensure cursor is at beginning
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Blood Donor Eligibility Task Setup Complete ==="
echo ""
echo "🩸 URGENT: Blood Bank Needs O+ Donors!"
echo ""
echo "📋 Your Task:"
echo "  1. Add column 'Next Eligible Date' (formula: Last Donation Date + 56)"
echo "  2. Add column 'Eligible Now?' (formula: IF(Next Eligible Date <= TODAY(), 'YES', 'NO'))"
echo "  3. Add column 'Urgent Match (O+)' (formula: IF(AND(Blood Type='O+', Eligible='YES'), 'URGENT', ''))"
echo "  4. Apply formulas to all donor rows"
echo "  5. Handle missing dates gracefully (use ISBLANK or IFERROR if needed)"
echo ""
echo "💡 Medical Context: Whole blood donors must wait 56 days between donations"
echo "🎯 Goal: Identify O+ donors who are eligible NOW for urgent blood drive"