#!/bin/bash
echo "=== Setting up college_roi_analysis task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Create the messy College Scorecard dataset
CSV_FILE="/home/ga/Documents/college_scorecard.csv"

# Write the Python script to generate the realistic messy CSV
python3 << 'PYEOF'
import csv
import os

csv_path = '/home/ga/Documents/college_scorecard.csv'

# Realistic representation of the federal College Scorecard dataset
data = [
    ["INSTNM", "STABBR", "PREDDEG", "GRAD_DEBT_MDN", "MD_EARN_WNE_P10"],
    ["University of Pennsylvania", "PA", "3", "16763", "95600"],
    ["Carnegie Mellon University", "PA", "3", "22500", "93400"],
    ["New York University", "NY", "3", "23000", "68000"],
    ["Swarthmore College", "PA", "3", "13500", "64400"],
    ["Community College of Philadelphia", "PA", "2", "8000", "32000"],
    ["Lehigh University", "PA", "3", "24000", "89000"],
    ["PA Secret School", "PA", "3", "NULL", "NULL"],
    ["Bucknell University", "PA", "3", "25000", "75800"],
    ["Rutgers University", "NJ", "3", "22000", "60000"],
    ["Villanova University", "PA", "3", "26000", "85200"],
    ["Drexel University", "PA", "3", "30000", "72400"],
    ["Temple University", "PA", "3", "25000", "56100"],
    ["Penn State University", "PA", "3", "26000", "55200"],
    ["University of Pittsburgh", "PA", "3", "26500", "58000"],
    ["Small PA College", "PA", "3", "PrivacySuppressed", "PrivacySuppressed"],
    ["Cornell University", "NY", "3", "14000", "85000"],
    ["West Chester University", "PA", "3", "24500", "51000"],
    ["Indiana University of PA", "PA", "3", "27000", "44000"],
    ["Slippery Rock University", "PA", "3", "25000", "47000"],
    ["Bryn Mawr College", "PA", "3", "19000", "61000"],
    ["Haverford College", "PA", "3", "15000", "62000"],
    ["Lafayette College", "PA", "3", "20000", "77000"],
    ["Franklin & Marshall College", "PA", "3", "22000", "63000"],
    ["Muhlenberg College", "PA", "3", "25000", "59000"],
    ["Dickinson College", "PA", "3", "19000", "60000"],
    ["Gettysburg College", "PA", "3", "22000", "58000"],
    ["Allegheny College", "PA", "3", "26000", "51000"],
    ["Messiah University", "PA", "3", "25000", "49000"],
    ["Widener University", "PA", "3", "27000", "60000"],
    ["Duquesne University", "PA", "3", "26000", "59000"]
]

with open(csv_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerows(data)

os.chmod(csv_path, 0o666)
PYEOF

chown ga:ga "$CSV_FILE" 2>/dev/null || true

# Launch WPS Spreadsheet with the CSV file
if ! pgrep -f "et" > /dev/null; then
    echo "Starting WPS Spreadsheet..."
    su - ga -c "DISPLAY=:1 et '$CSV_FILE' &"
    sleep 5
fi

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Spreadsheet\|et"; then
        break
    fi
    sleep 1
done

# Maximize window (CRITICAL for agent visibility)
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "college_scorecard" 2>/dev/null || true

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="