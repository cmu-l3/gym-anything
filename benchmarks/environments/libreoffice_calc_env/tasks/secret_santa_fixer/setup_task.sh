#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Secret Santa Fixer Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with intentional violations
cat > /home/ga/Documents/secret_santa.csv << 'CSVEOF'
Name,Spouse,Gives To,Budget
Alice,Bob,Alice,$25
Bob,Alice,Carol,25 dollars
Carol,Dave,Dave,$30
Dave,Carol,,thirty
Emma,,Frank,$25
Frank,,Grace,25
Grace,Henry,Ivan,$20
Henry,Grace,Jack,25
Ivan,,Kelly,$25
Jack,,Emma,$25
Kelly,Leo,Leo,25 dollars
Leo,Kelly,Mike,$25
Mike,,Nina,25
Nina,,Oscar,$25
Oscar,,Bob,25
CSVEOF

chown ga:ga /home/ga/Documents/secret_santa.csv
chmod 666 /home/ga/Documents/secret_santa.csv

echo "✅ Created secret_santa.csv with intentional violations:"
echo "   - Alice gives to Alice (self-assignment)"
echo "   - Carol gives to Dave (spouse pairing)"
echo "   - Dave has no assignment (missing)"
echo "   - Kelly gives to Leo (spouse pairing)"
echo "   - Budgets are inconsistent formats"

# Launch LibreOffice Calc with the CSV
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/secret_santa.csv > /tmp/calc_secret_santa.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_secret_santa.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice" 90; then
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

# Position cursor at A1 to show the data
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Secret Santa Fixer Task Setup Complete ==="
echo ""
echo "📋 Current Problems to Fix:"
echo "  ❌ Alice is assigned to herself (self-assignment)"
echo "  ❌ Carol is assigned to Dave (her spouse)"
echo "  ❌ Dave has no assignment (empty cell)"
echo "  ❌ Kelly is assigned to Leo (her spouse)"
echo "  ❌ Budgets are in inconsistent formats"
echo ""
echo "✅ Requirements:"
echo "  1. Fix all self-assignments"
echo "  2. Fix all spouse pairings"
echo "  3. Complete missing assignments"
echo "  4. Standardize budgets to numeric values (15-50 range)"
echo "  5. Ensure valid cycle (everyone gives to 1, receives from 1)"
echo ""
echo "💡 Hint: Use the Spouse column to identify married couples"