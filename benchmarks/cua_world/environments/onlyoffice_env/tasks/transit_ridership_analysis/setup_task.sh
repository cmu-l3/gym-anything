#!/bin/bash
set -euo pipefail

echo "=== Setting up Transit Ridership Analysis Task ==="

# Record task start timestamp for anti-gaming verification
echo $(date +%s) > /tmp/transit_task_start_ts

# Kill existing processes
if pgrep -f "onlyoffice-desktopeditors|DesktopEditors" > /dev/null; then
    pkill -f "onlyoffice-desktopeditors|DesktopEditors" || true
    sleep 2
fi

WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

CSV_PATH="$WORKSPACE_DIR/apc_ridership_q1_2024.csv"

# Generate deterministic dataset and ground truth values
cat > /tmp/create_transit_data.py << 'PYEOF'
#!/usr/bin/env python3
import csv
import json
from datetime import date, timedelta
import random

random.seed(42)
start_date = date(2024, 1, 1)
# Create 50 routes
routes = [str(i) for i in range(1, 49)] + ['88X', '99X']

csv_path = "/home/ga/Documents/Spreadsheets/apc_ridership_q1_2024.csv"
gt_path = "/tmp/transit_ground_truth.json"

total_sys_boardings = 0
total_sys_cost = 0.0
total_sys_revenue = 0.0

with open(csv_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['Service_Date', 'Route_ID', 'Route_Type', 'Day_Type', 'Total_Boardings', 'Revenue_Hours', 'Revenue_Miles', 'Fare_Revenue'])
    
    # 91 days in Q1 (Jan 1 to Mar 31)
    for i in range(91):
        d = start_date + timedelta(days=i)
        is_wkdy = d.weekday() < 5
        day_type = 'Wkdy' if is_wkdy else ('Sat' if d.weekday() == 5 else 'Sun')
        
        for r in routes:
            if r == '15':
                rtype = 'BRT'
                boardings = 3000 if is_wkdy else 1200
                hours = 18.0
                miles = 250.0
                fare = boardings * 1.15
            elif r == '88X':
                rtype = 'Express'
                boardings = 100 if is_wkdy else 20
                hours = 8.0
                miles = 150.0
                fare = boardings * 2.50
            elif r == '99X':
                rtype = 'Express'
                boardings = 150 if is_wkdy else 30
                hours = 9.0
                miles = 160.0
                fare = boardings * 2.50
            else:
                rtype = 'Local'
                base_b = random.randint(300, 1000)
                boardings = base_b if is_wkdy else int(base_b * 0.4)
                hours = round(random.uniform(10, 16), 1)
                miles = round(hours * 12.5, 1)
                fare = boardings * 0.85
                
            writer.writerow([d.strftime('%Y-%m-%d'), r, rtype, day_type, boardings, hours, miles, round(fare, 2)])
            
            total_sys_boardings += boardings
            cost = (hours * 135.50) + (miles * 4.25)
            total_sys_cost += cost
            total_sys_revenue += fare

# Calculate exact ground truth expected in verifier
gt = {
    "route_15_total_boardings": 226200,
    "route_15_avg_wkdy": 3000,
    "route_88x_daily_cost": 1721.5,
    "route_88x_frr": 17550.0 / 156656.5,
    "total_system_boardings": total_sys_boardings,
    "system_frr": total_sys_revenue / total_sys_cost
}

with open(gt_path, 'w') as f:
    json.dump(gt, f)

print("Data generation complete.")
PYEOF

python3 /tmp/create_transit_data.py
chown ga:ga "$CSV_PATH"
chown ga:ga "/tmp/transit_ground_truth.json"

# Launch OnlyOffice with the created CSV
if [ -f "/home/ga/launch_spreadsheet.sh" ]; then
    su - ga -c "DISPLAY=:1 /home/ga/launch_spreadsheet.sh '$CSV_PATH' >/dev/null 2>&1 &"
else
    su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$CSV_PATH' >/dev/null 2>&1 &"
fi

# Wait for application window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "ONLYOFFICE\|Desktop Editors"; then
        break
    fi
    sleep 1
done

# Focus and maximize window
DISPLAY=:1 wmctrl -a "ONLYOFFICE" 2>/dev/null || true
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot showing loaded data
su - ga -c "DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null" || true

echo "=== Setup Complete ==="