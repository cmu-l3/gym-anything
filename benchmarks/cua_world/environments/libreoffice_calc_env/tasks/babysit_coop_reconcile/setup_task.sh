#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Babysitting Co-op Reconciliation Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with messy transaction data
cat > /home/ga/Documents/babysit_coop_transactions.csv << 'EOF'
Date,Babysitter_Family,Child_Family,Hours,Notes
2024-02-01,Johnson,Patel,2.5,Friday evening
2024-02-03,Patel,Johnson,3:00,Saturday afternoon
2024-02-05,Kim,Rodriguez,evening,Date night sitting
2024-02-07,Rodriguez,Chen,2.0,After school pickup
2024-02-09,Chen,Williams,date night,Weekend evening out
2024-02-11,Williams,Thompson,2:30,Doctor appointment
2024-02-13,Thompson,Davis,3.5,Midweek evening
2024-02-15,Davis,Johnson,afternoon,Short afternoon errand
2024-02-17,Kim,Patel,3.0,Friday night
2024-02-19,Johnson,Rodriguez,2:15,Evening event
2024-02-21,Patel,Kim,2.5,Saturday morning activity
2024-02-23,Chen,Davis,3:30,Concert evening
2024-02-25,Kim,Williams,evening,Thursday date night
2024-02-27,Rodriguez,Thompson,1.5,Quick grocery run
2024-02-29,Williams,Kim,afternoon,Afternoon appointment
2024-03-02,Thompson,Chen,2.0,After school care
2024-03-04,Davis,Williams,3:00,Friday evening dinner
2024-03-06,Kim,Chen,date night,Anniversary dinner
2024-03-08,Patel,Davis,2:45,Theater matinee
2024-03-10,Johnson,Thompson,evening,Weekend evening
2024-03-12,Chen,Patel,2.5,Midweek evening
2024-03-14,Williams,Rodriguez,1:30,Short errand
2024-03-16,Davis,Thompson,afternoon,Saturday afternoon
2024-03-18,Rodriguez,Williams,2.0,Evening activity
EOF

# Set permissions
sudo chown ga:ga /home/ga/Documents/babysit_coop_transactions.csv
sudo chmod 666 /home/ga/Documents/babysit_coop_transactions.csv

echo "✅ Created babysit_coop_transactions.csv with messy time formats"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/babysit_coop_transactions.csv > /tmp/calc_coop_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_coop_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
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

# Move cursor to top of document
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Babysitting Co-op Reconciliation Task Setup Complete ==="
echo "📋 Transaction log opened with messy time formats"
echo ""
echo "📝 Instructions:"
echo "  1. Standardize Hours column (D) to decimal format:"
echo "     - '3:00' → 3.0, '2:30' → 2.5, '2:15' → 2.25"
echo "     - 'evening' → 3.0, 'afternoon' → 2.0, 'date night' → 4.0"
echo "  2. Create summary table with columns:"
echo "     - Family Name | Credits Given | Credits Received | Balance | Status"
echo "  3. Use SUMIF formulas to calculate credits given and received"
echo "  4. Calculate Balance = Credits Given - Credits Received"
echo "  5. Flag families with |balance| > 5 hours:"
echo "     - 'Owes Hours' (balance < -5)"
echo "     - 'Owed Hours' (balance > 5)"
echo "     - 'Balanced' (within ±5 hours)"
echo "  6. Apply conditional formatting (Red/Yellow/Green)"
echo ""
echo "🎯 Expected outcome: Clean transaction data + summary table with 8 families"