#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Fantasy Football Lineup Optimizer Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create roster CSV with projected player statistics
cat > /home/ga/Documents/roster_week7.csv << 'EOF'
Player Name,Position,Proj Rush Yds,Proj Rec Yds,Proj Receptions,Proj Rush TDs,Proj Rec TDs,Proj Pass Yds,Proj Pass TDs
Patrick Mahomes,QB,10,0,0,0,0,285,2.2
Josh Allen,QB,45,0,0,0.3,0,270,2.5
Derrick Henry,RB,95,15,1.5,1.1,0,0,0
Austin Ekeler,RB,55,45,4.5,0.6,0.3,0,0
Tony Pollard,RB,70,25,2.5,0.7,0.2,0,0
James Conner,RB,60,20,2,0.5,0.1,0,0
Stefon Diggs,WR,0,85,7.5,0,0.8,0,0
Tyreek Hill,WR,0,90,8,0,0.9,0,0
CeeDee Lamb,WR,0,75,6.5,0,0.6,0,0
Amon-Ra St. Brown,WR,0,80,7,0,0.7,0,0
DK Metcalf,WR,0,70,6,0,0.5,0,0
Travis Kelce,TE,0,80,7,0,0.9,0,0
Darren Waller,TE,0,60,5.5,0,0.5,0,0
George Kittle,TE,0,65,6,0,0.6,0,0
Tyler Lockett,WR,0,55,5,0,0.4,0,0
Kenneth Walker,RB,50,15,1.5,0.4,0.1,0,0
EOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/roster_week7.csv
sudo chmod 666 /home/ga/Documents/roster_week7.csv

echo "✅ Created roster CSV with player projections"

# Launch LibreOffice Calc with the CSV
echo "Launching LibreOffice Calc with roster..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/roster_week7.csv > /tmp/calc_fantasy_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_fantasy_task.log || true
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

# Ensure cursor is at A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Fantasy Football Lineup Optimizer Task Setup Complete ==="
echo ""
echo "📋 Task: Optimize your fantasy football starting lineup"
echo ""
echo "📊 Scoring Rules (PPR):"
echo "  • Rushing Yards: 0.1 pts/yd"
echo "  • Receiving Yards: 0.1 pts/yd"
echo "  • Receptions: 1 pt each"
echo "  • Rushing TDs: 6 pts each"
echo "  • Receiving TDs: 6 pts each"
echo "  • Passing Yards: 0.04 pts/yd"
echo "  • Passing TDs: 4 pts each"
echo ""
echo "🎯 Lineup Requirements:"
echo "  • 1 QB"
echo "  • 2 RB"
echo "  • 2 WR"
echo "  • 1 TE"
echo "  • 1 FLEX (RB/WR/TE)"
echo ""
echo "✅ To Complete:"
echo "  1. Create 'Projected Points' column with scoring formula"
echo "  2. Calculate points for all players"
echo "  3. Create 'Lineup Status' column"
echo "  4. Mark optimal 7 starters as 'START'"
echo "  5. Mark remaining players as 'BENCH'"
echo "  6. Verify total projected points for starters"