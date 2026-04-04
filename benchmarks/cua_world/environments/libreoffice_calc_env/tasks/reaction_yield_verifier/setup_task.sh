#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Chemical Reaction Yield Verification Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with reaction data
# Note: RXN-001, RXN-004, and RXN-007 have intentionally incorrect reported yields
cat > /home/ga/Documents/reaction_data.csv << 'CSVEOF'
Reaction_ID,Theoretical_Yield_g,Actual_Yield_g,Reported_Yield_%
RXN-001,5.2,4.1,82.5
RXN-002,3.8,3.6,94.7
RXN-003,6.5,5.2,80.0
RXN-004,4.1,3.3,79.5
RXN-005,7.3,6.8,93.2
RXN-006,2.9,2.4,82.8
RXN-007,5.7,4.9,85.0
RXN-008,4.5,3.8,84.4
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/reaction_data.csv
sudo chmod 666 /home/ga/Documents/reaction_data.csv

echo "✅ Created reaction_data.csv with 8 reactions (3 contain calculation errors)"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/reaction_data.csv > /tmp/calc_reaction_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_reaction_task.log || true
    # Don't exit, allow task to continue
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit, allow task to continue
fi

sleep 2

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
        
        # Move cursor to cell A1 to ensure consistent starting position
        safe_xdotool ga :1 key ctrl+Home
        sleep 0.3
    fi
fi

echo "=== Chemical Reaction Yield Verification Task Setup Complete ==="
echo ""
echo "📋 TASK OVERVIEW:"
echo "   A chemistry graduate student suspects calculation errors in a published paper."
echo "   You must verify the reported reaction yields by recalculating from raw data."
echo ""
echo "📝 INSTRUCTIONS:"
echo "   1. Click on cell E1 and add header: 'Calculated_Yield_%'"
echo "   2. Click on cell E2 (first data row)"
echo "   3. Enter formula: =(C2/B2)*100"
echo "   4. Copy formula down to E9 (all reaction rows)"
echo "   5. Click on cell F1 and add header: 'Discrepancy_pp'"
echo "   6. Click on cell F2"
echo "   7. Enter formula: =E2-D2"
echo "   8. Copy formula down to F9"
echo "   9. Review results: discrepancies >0.5 indicate calculation errors"
echo ""
echo "💡 HINTS:"
echo "   - Use Ctrl+C and Ctrl+V to copy formulas efficiently"
echo "   - Check that formulas update cell references (E3 uses C3/B3, not C2/B2)"
echo "   - Expected: 2-3 reactions will show significant discrepancies (>0.5 pp)"
echo "   - Small discrepancies (±0.1 to 0.5) are acceptable rounding differences"