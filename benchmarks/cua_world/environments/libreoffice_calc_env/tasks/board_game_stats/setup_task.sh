#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Board Game Stats Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create game log CSV with realistic board game night data
cat > /home/ga/Documents/game_log.csv << 'EOF'
Date,GameName,Winner
2024-01-05,Catan,Alex
2024-01-05,Ticket to Ride,Blake
2024-01-12,Carcassonne,Casey
2024-01-12,Splendor,Blake
2024-01-19,Catan,Alex
2024-01-19,Azul,Drew
2024-01-26,7 Wonders,Ellis
2024-01-26,Ticket to Ride,Alex
2024-02-02,Catan,Blake
2024-02-02,Splendor,Alex
2024-02-09,Carcassonne,Casey
2024-02-09,Azul,Blake
2024-02-16,Ticket to Ride,Drew
2024-02-16,Catan,Alex
2024-02-23,7 Wonders,Casey
2024-02-23,Splendor,Blake
2024-03-01,Carcassonne,Drew
2024-03-01,Ticket to Ride,Alex
2024-03-08,Catan,Blake
2024-03-08,Azul,Casey
2024-03-15,Splendor,Ellis
2024-03-15,7 Wonders,Blake
2024-03-22,Catan,Casey
2024-03-22,Ticket to Ride,Drew
2024-03-29,Azul,Ellis
EOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/game_log.csv
sudo chmod 666 /home/ga/Documents/game_log.csv

echo "✅ Created game log CSV with 25 game records"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/game_log.csv > /tmp/calc_game_stats.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_game_stats.log
    # Don't exit - continue for robustness
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit - continue for robustness
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

# Move to top of document
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Board Game Stats Task Setup Complete ==="
echo "📊 Game Log Data Ready"
echo "📝 Instructions:"
echo "  1. Review the GameLog data (Date, GameName, Winner)"
echo "  2. Create a Player Statistics section"
echo "  3. List all players: Alex, Blake, Casey, Drew, Ellis"
echo "  4. Use COUNTIF formulas to count wins per player"
echo "  5. Calculate games played for each player"
echo "  6. Calculate win rate: (Wins/Games)*100"
echo "  7. Identify the player with highest win rate"
echo ""
echo "💡 Hint: =COUNTIF(C:C,\"PlayerName\") counts wins"
echo "💡 Hint: Win Rate = (Wins/Games)*100 or format as percentage"