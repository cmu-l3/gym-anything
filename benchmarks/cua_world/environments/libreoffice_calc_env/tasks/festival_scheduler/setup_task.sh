#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Festival Scheduler Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create film submissions CSV with messy duration data
cat > /home/ga/Documents/film_submissions.csv << 'EOF'
Film_Title,Director,Genre,Duration_Original
The Long Night,Sarah Chen,Drama,2h 15m
Quick Cuts,Mike Rodriguez,Documentary,45
Sunset Dreams,Emma Thompson,Romance,1:35
City Lights,James Park,Comedy,about 95 minutes
Silent Witness,Lisa Kumar,Thriller,105
Autumn Tales,David Wong,Drama,1h 50m
Morning Coffee,Ana Garcia,Comedy,82
Desert Winds,Omar Hassan,Documentary,38
Neon Dreams,Kelly O'Brien,Sci-Fi,2:10
Family Reunion,Tom Martinez,Drama,118
Late Night Stories,Jessica Lee,Comedy,1:25
The Last Dance,Robert Brown,Documentary,52
EOF

# Create venue information CSV
cat > /home/ga/Documents/venue_info.csv << 'EOF'
Venue_Name,Capacity,Available_Screens,Max_Daily_Hours
Main Theater,150,1,8
Gallery Space,50,1,8
EOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/film_submissions.csv
sudo chown ga:ga /home/ga/Documents/venue_info.csv
sudo chmod 644 /home/ga/Documents/film_submissions.csv
sudo chmod 644 /home/ga/Documents/venue_info.csv

echo "✅ Created film_submissions.csv and venue_info.csv"

# Launch LibreOffice Calc with the film submissions file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/film_submissions.csv > /tmp/calc_festival_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_festival_task.log || true
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

# Position cursor at cell E1 (ready to add Duration_Minutes header)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key Right Right Right Right
sleep 0.3

echo "=== Festival Scheduler Task Setup Complete ==="
echo ""
echo "📋 Task Instructions:"
echo "  1. Create 'Duration_Minutes' column to standardize all duration formats to integer minutes"
echo "     - Parse formats: '90', '1:35', '2h 15m', 'about 95 minutes'"
echo "  2. Create 'Total_Block_Minutes' column (Duration + 20 min buffer for Q&A and transition)"
echo "  3. Create 'Assigned_Venue' column:"
echo "     - Films >120 min → 'Main Theater'"
echo "     - Documentaries <45 min → 'Gallery Space'"
echo "     - Others → distribute reasonably"
echo "  4. Create 'Time_Slot' column with available slots:"
echo "     - 2:00 PM (fits films ≤110 min)"
echo "     - 4:00 PM (fits films ≤140 min)"
echo "     - 6:30 PM (fits films ≤110 min)"
echo "     - 8:30 PM (fits films ≤90 min)"
echo "  5. Create 'Conflict_Flag' column to detect scheduling conflicts"
echo ""
echo "💡 Venue info available in: /home/ga/Documents/venue_info.csv"
echo "💡 Available time slots: 2:00 PM, 4:00 PM, 6:30 PM, 8:30 PM"