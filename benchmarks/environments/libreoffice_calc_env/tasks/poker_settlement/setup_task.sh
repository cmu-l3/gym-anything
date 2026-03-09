#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Poker Settlement Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create poker night CSV data
cat > /home/ga/Documents/poker_night_data.csv << 'CSVEOF'
Player,Initial Buy-in,Rebuy 1,Rebuy 2,Final Chips
Alice,50,25,,105
Bob,50,,,35
Charlie,50,25,25,185
Dana,50,25,,60
Eve,50,,,25
Frank,50,25,25,120
Grace,50,25,,40
Henry,50,25,,30
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/poker_night_data.csv
sudo chmod 666 /home/ga/Documents/poker_night_data.csv

echo "✅ Created poker_night_data.csv with 8 players"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/poker_night_data.csv > /tmp/calc_poker_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_poker_task.log || true
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

# Ensure cursor is at cell A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Poker Settlement Task Setup Complete ==="
echo ""
echo "🎰 POKER NIGHT RECONCILIATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Data: 8 players with varying buy-ins and chip counts"
echo ""
echo "📝 Required Steps:"
echo "  1. Add column F header: 'Total Buy-in'"
echo "  2. In F2, create formula: =SUM(B2:D2)"
echo "  3. Copy F2 formula down to F9 (all players)"
echo "  4. Add column G header: 'Net Position'"
echo "  5. In G2, create formula: =E2-F2"
echo "  6. Copy G2 formula down to G9 (all players)"
echo "  7. Verify zero-sum: Create cell with =SUM(G2:G9) (should be 0)"
echo "  8. Apply conditional formatting to G2:G9 (green=positive, red=negative)"
echo "  9. Sort all data by column G (Net Position) in descending order"
echo ""
echo "✅ Success criteria:"
echo "  • Total Buy-in formulas correct (SUM of buy-ins)"
echo "  • Net Position formulas correct (Chips - Buy-ins)"
echo "  • Zero-sum validated (total net = $0 ± $1)"
echo "  • Data organized (sorted by net position)"