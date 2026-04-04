#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Personal Lending Tracker Cleanup Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create lending log CSV with realistic messy data
# Some items returned (have return date), some still out (blank return date)
# Mix of old and recent dates to test Days On Loan calculation
cat > /home/ga/Documents/lending_log.csv << 'CSVEOF'
Item Name,Borrowed By,Lent Date,Return Date,Estimated Value
Circular Saw,Tom Martinez,2024-09-15,,120
"Educated" Book,Sarah Chen,2024-11-20,2024-12-05,18
Pressure Washer,Mike Johnson,2024-08-01,,200
Camping Tent,Lisa Park,2024-12-10,2024-12-18,150
Pasta Maker,Janet Williams,2024-08-22,,80
Board Game: Wingspan,Chris Anderson,2024-11-30,,60
Hedge Trimmer,Tom Martinez,2024-12-01,2024-12-08,90
Kayak Paddle,Mike Johnson,2024-07-15,,65
Instant Pot,Sarah Chen,2024-12-15,2024-12-22,95
Extension Ladder,Bob Harris,2024-10-01,,175
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/lending_log.csv
sudo chmod 666 /home/ga/Documents/lending_log.csv

echo "✅ Created lending_log.csv with 10 items (5 returned, 5 still out)"

# Launch LibreOffice Calc with the CSV
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/lending_log.csv > /tmp/calc_lending_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_lending_task.log || true
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

# Position cursor at cell A1 (top-left)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Personal Lending Tracker Cleanup Task Setup Complete ==="
echo ""
echo "📋 TASK INSTRUCTIONS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Your lending log is messy - some items are still out!"
echo ""
echo "1️⃣  ADD 'Days On Loan' COLUMN (Column F):"
echo "   • Header: Days On Loan"
echo "   • Formula: =IF(ISBLANK(D2), TODAY()-C2, \"\")"
echo "   • Copy to all rows (F2:F11)"
echo ""
echo "2️⃣  CALCULATE TOTAL OUTSTANDING VALUE:"
echo "   • Pick a cell below data (e.g., E13)"
echo "   • Label: 'Total Outstanding:'"
echo "   • Formula: =SUMIF(D:D, \"\", E:E)"
echo ""
echo "3️⃣  HIGHLIGHT OVERDUE ITEMS (>30 days):"
echo "   • Select F2:F11"
echo "   • Format → Conditional Formatting"
echo "   • Rule: Cell value > 30"
echo "   • Format: Red background or text"
echo ""
echo "💡 TIP: Blank Return Date = item still on loan"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"