#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Babysitting Co-op Time Bank Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with messy transaction data (intentional name inconsistencies)
cat > /home/ga/Documents/babysit_coop_transactions.csv << 'EOF'
Date,Provider Family,Client Family,Hours
2024-01-05,Johnson,Martinez Family,3.0
2024-01-08,Chen,Johnsons,2.5
2024-01-10,Martinez,Chen Family,4.0
2024-01-12,Rodriguez Family,Johnson,3.5
2024-01-15,Chen Family,Rodriguez,2.0
2024-01-18,Smith,Davis Family,2.5
2024-01-20,Martinez Family,Smiths,3.0
2024-01-22,Davis,Chen,1.5
2024-01-25,Johnsons,Rodriguez Family,4.0
2024-01-28,Rodriguez,Smith,2.5
2024-02-01,Chen,Martinez,3.5
2024-02-03,Johnson Family,Davis,2.0
2024-02-05,Davis Family,Johnson,4.5
2024-02-08,Smith,Chen Family,3.0
2024-02-10,Martinez,Rodriguez,1.5
2024-02-12,Rodriguez Family,Smiths,2.0
2024-02-15,Chen Family,Johnson,3.5
2024-02-18,Johnson,Smith,2.0
2024-02-20,Davis,Martinez Family,3.0
2024-02-22,Smiths,Rodriguez,4.0
2024-02-25,Martinez Family,Davis,2.5
2024-02-28,Rodriguez,Chen,1.5
2024-03-02,Johnson,Rodriguez Family,3.0
2024-03-05,Chen,Davis Family,2.5
2024-03-08,Davis Family,Martinez,4.0
2024-03-10,Smith,Johnson,1.5
EOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/babysit_coop_transactions.csv
sudo chmod 666 /home/ga/Documents/babysit_coop_transactions.csv

echo "✅ Created transaction log with 26 transactions"

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

# Move cursor to cell A1 to show full data
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Babysitting Co-op Time Bank Task Setup Complete ==="
echo ""
echo "📋 Transaction Log Overview:"
echo "  - 6 families participating in time-bank"
echo "  - 26 transactions over 3 months"
echo "  - Intentional name inconsistencies (e.g., 'Johnson' vs 'Johnsons' vs 'Johnson Family')"
echo ""
echo "📝 Your Task:"
echo "  1. Create a summary table (in columns F-I or similar)"
echo "  2. Headers: Family Name | Hours Earned | Hours Spent | Net Balance"
echo "  3. Use SUMIF formulas to calculate earned/spent hours"
echo "  4. Calculate Net Balance = Hours Earned - Hours Spent"
echo "  5. Apply conditional formatting: highlight cells < -5 (red background)"
echo ""
echo "💡 Hints:"
echo "  - Hours Earned: =SUMIF(\$B\$2:\$B\$27, F2, \$D\$2:\$D\$27)"
echo "  - Hours Spent: =SUMIF(\$C\$2:\$C\$27, F2, \$D\$2:\$D\$27)"
echo "  - Balance: =G2-H2"
echo "  - Conditional Format: Format → Conditional → Cell value < -5"