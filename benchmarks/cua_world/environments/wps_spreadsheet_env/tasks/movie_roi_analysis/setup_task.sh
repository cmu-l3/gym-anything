#!/bin/bash
echo "=== Setting up movie_roi_analysis task ==="

CSV_FILE="/home/ga/Documents/movies.csv"
OUTPUT_FILE="/home/ga/Documents/Movie_ROI_Analysis.xlsx"

# Remove any old files
rm -f "$CSV_FILE" 2>/dev/null || true
rm -f "$OUTPUT_FILE" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Generate realistic movie data CSV
cat > "$CSV_FILE" << 'CSVEOF'
Title,Genre,Budget,Gross,Runtime
Explosive Force,Action,150000000,450000000,115
Laugh Factory,Comedy,20000000,60000000,85
Tears in the Rain,Drama,15000000,25000000,130
The Dark House,Horror,5000000,85000000,92
Cartoon Animals,Animation,80000000,300000000,95
Indie Zero Budget,Drama,0,150000,105
Action Flop,Action,200000000,50000000,140
Short Comedy,Comedy,10000000,12000000,82
Epic Historical,Drama,75000000,120000000,180
Scary Jump,Horror,2000000,45000000,88
Animated Sequel,Animation,100000000,500000000,100
Unknown Length,Action,50000000,60000000,0
Missing Budget,Comedy,,2000000,91
Average Action,Action,60000000,130000000,110
Sad Story,Drama,12000000,8000000,118
Space Battles,Action,180000000,600000000,125
College Pranks,Comedy,15000000,45000000,89
Family Matters,Drama,25000000,35000000,112
Cabin Ghost,Horror,1000000,20000000,80
Talking Cars,Animation,120000000,400000000,98
CSVEOF

chown ga:ga "$CSV_FILE" 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Start WPS Spreadsheet with the CSV file
if ! pgrep -f "et " > /dev/null; then
    echo "Starting WPS Spreadsheet..."
    su - ga -c "DISPLAY=:1 et '$CSV_FILE' &"
    sleep 5
fi

# Wait for window to appear
for i in {1..15}; do
    if DISPLAY=:1 wmctrl -l | grep -i "movies.csv"; then
        break
    fi
    sleep 1
done

# Maximize window (CRITICAL for agent visibility)
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "movies.csv" 2>/dev/null || true

# Take screenshot of initial state (for evidence)
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="