#!/bin/bash
set -euo pipefail

# Source utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Theme Park Wait Time Analysis Task ==="

# Record task start timestamp for anti-gaming
echo $(date +%s) > /tmp/theme_park_wait_time_analysis_start_ts

# Cleanup any existing OnlyOffice processes
cleanup_temp_files
kill_onlyoffice ga
sleep 1

# Setup workspace
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
CSV_PATH="$WORKSPACE_DIR/wait_times_july_week1.csv"

# Generate realistic theme park wait time data
cat > /tmp/create_wait_time_data.py << 'PYEOF'
#!/usr/bin/env python3
import csv
import sys
import random
from datetime import datetime, timedelta

output_path = sys.argv[1]
random.seed(2024)  # Deterministic generation for verifier consistency

rides = [
    "Space Mountain",
    "Splash Mountain",
    "Seven Dwarfs Mine Train",
    "Peter Pan's Flight",
    "Pirates of the Caribbean"
]

start_date = datetime(2019, 7, 1)

with open(output_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['date', 'datetime', 'hour_of_day', 'ride_name', 'posted_wait_mins', 'actual_wait_mins'])
    
    for day in range(7):
        current_date = start_date + timedelta(days=day)
        date_str = current_date.strftime('%m/%d/%Y')
        
        # Park hours: 9 AM to 10 PM (22:00)
        for hour in range(9, 23):
            # Peak multiplier: hour 14 (2 PM) is peak (1.0), tapers off at ends
            peak_mult = 1.0 - abs(14 - hour) * 0.08
            
            for ride in rides:
                # 6 to 12 readings per hour per ride
                for _ in range(random.randint(6, 12)):
                    dt = current_date + timedelta(hours=hour, minutes=random.randint(0, 59))
                    
                    base_wait = 30
                    discrepancy_mean = 5
                    
                    if ride == "Seven Dwarfs Mine Train":
                        base_wait = 80
                        discrepancy_mean = 10
                    elif ride == "Space Mountain":
                        base_wait = 55
                        discrepancy_mean = 15  # Known to overstate wait times heavily
                    elif ride == "Peter Pan's Flight":
                        base_wait = 60
                        discrepancy_mean = 5
                    elif ride == "Splash Mountain":
                        base_wait = 50
                        discrepancy_mean = 5
                    elif ride == "Pirates of the Caribbean":
                        base_wait = 30
                        discrepancy_mean = 5
                        
                    # Calculate true actual wait
                    actual_wait = max(5, int((base_wait + random.randint(-15, 15)) * peak_mult))
                    
                    # Calculate posted wait (usually higher than actual, rounded to nearest 5)
                    posted_wait = actual_wait + int(random.gauss(discrepancy_mean, 5))
                    posted_wait = max(5, int(round(posted_wait / 5.0) * 5))
                    
                    # 15% chance of missing physical timing card (actual wait is blank)
                    if random.random() < 0.15:
                        actual_val = ""
                    else:
                        actual_val = actual_wait
                        
                    writer.writerow([date_str, dt.isoformat(), hour, ride, posted_wait, actual_val])

print(f"Successfully generated dataset at {output_path}")
PYEOF

chmod +x /tmp/create_wait_time_data.py
sudo -u ga /tmp/create_wait_time_data.py "$CSV_PATH"

# Ensure OnlyOffice starts fresh with a blank workbook
echo "Starting ONLYOFFICE..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors --new:cell > /tmp/onlyoffice_task.log 2>&1 &"
sleep 5

# Wait for and maximize window
wait_for_window "Desktop Editors\|ONLYOFFICE" 30 || true
WID=$(get_onlyoffice_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
sleep 2
su - ga -c "DISPLAY=:1 import -window root /tmp/theme_park_wait_time_analysis_initial.png" || true

echo "=== Setup Complete ==="