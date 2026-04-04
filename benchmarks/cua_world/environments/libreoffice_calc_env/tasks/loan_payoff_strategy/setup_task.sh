#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Loan Payoff Strategy Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with loan data
cat > /home/ga/Documents/my_loans.csv << 'CSVEOF'
Loan Name,Current Balance,Interest Rate (Annual %),Minimum Payment
Federal Direct,12500,4.5,150
Private Bank A,8200,7.2,120
Perkins Loan,3800,5.0,75
Private Bank B,6100,6.8,95
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/my_loans.csv
sudo chmod 666 /home/ga/Documents/my_loans.csv

echo "✅ Created loan data CSV: /home/ga/Documents/my_loans.csv"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc with loan data..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/my_loans.csv > /tmp/calc_loan_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_loan_task.log || true
    # Don't exit - continue for robustness
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit - continue for robustness
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
        echo "✅ Calc window focused"
        # Maximize window
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

# Ensure cursor is at cell A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Loan Payoff Strategy Task Setup Complete ==="
echo ""
echo "📊 Scenario: You have 4 student loans and $200/month extra to pay."
echo "🎯 Goal: Determine which loan to prioritize to minimize total interest."
echo ""
echo "📝 Tasks to complete:"
echo "  1. Calculate monthly interest rate (Annual % / 12)"
echo "  2. Calculate monthly interest charge ($)"
echo "  3. Calculate principal portion of payment"
echo "  4. Sort loans by interest rate (highest first)"
echo "  5. Identify priority loan for extra payments"
echo "  6. Apply currency and percentage formatting"
echo ""
echo "💡 Strategy tip: Pay highest interest rate first (avalanche method)"