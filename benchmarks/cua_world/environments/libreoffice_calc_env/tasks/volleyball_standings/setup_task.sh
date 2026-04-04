#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Volleyball Standings Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create initial standings CSV (no formulas, just raw data)
cat > /home/ga/Documents/volleyball_standings.csv << 'CSVEOF'
Team,Wins,Losses,Points,Win %
Spikers United,6,2,,
Net Results,5,3,,
Block Party,7,1,,
Set Point,4,4,,
Volley Llamas,3,5,,
Serve-ivors,6,2,,
Dig Deep,2,6,,
Bump & Run,5,3,,
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/volleyball_standings.csv
sudo chmod 666 /home/ga/Documents/volleyball_standings.csv

echo "✅ Created volleyball_standings.csv with 8 teams"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc with standings data..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/volleyball_standings.csv > /tmp/calc_volleyball.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_volleyball.log || true
    # Don't exit, continue anyway
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit, continue anyway
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
        # Maximize window for better visibility
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

# Position cursor at A1 (top-left)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Volleyball Standings Task Setup Complete ==="
echo "📊 Task Instructions:"
echo "  League Scoring Rule: Win = 3 points, Loss = 1 point"
echo ""
echo "  Step 1: Click on cell D2 (first team's Points cell)"
echo "  Step 2: Enter formula: =(B2*3)+C2"
echo "  Step 3: Copy formula down to D3:D9 (all teams)"
echo ""
echo "  Step 4: Click on cell E2 (first team's Win % cell)"
echo "  Step 5: Enter formula: =B2/(B2+C2)"
echo "  Step 6: Copy formula down to E3:E9 (all teams)"
echo ""
echo "  Step 7: Select data range A1:E9 (all data including headers)"
echo "  Step 8: Open Data → Sort"
echo "  Step 9: Sort Key 1 = Column D (Points), Order = Descending"
echo "  Step 10: Sort Key 2 = Column E (Win %), Order = Descending"
echo "  Step 11: Click OK to apply sort"
echo ""
echo "💡 Expected: Teams with most points ranked first, ties broken by win percentage"