#!/bin/bash
set -euo pipefail

echo "=== Setting up evaluate_public_works_bids task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Remove any existing files
rm -f /home/ga/Documents/raw_bid_tabulation.csv 2>/dev/null || true
rm -f /home/ga/Documents/bid_evaluation.xlsx 2>/dev/null || true

# Generate realistic public works bid data
cat > /home/ga/Documents/raw_bid_tabulation.csv << 'CSVEOF'
Item_No,Description,Quantity,Unit,Eng_Unit_Price,Apex_Unit_Price,Titan_Unit_Price,Horizon_Unit_Price
1,Mobilization,1,LS,50000.00,80000.00,55000.00,60000.00
2,Traffic Control,1,LS,25000.00,30000.00,20000.00,35000.00
3,Clearing and Grubbing,1,LS,10000.00,12000.00,25000.00,11000.00
4,Unclassified Excavation,5000,CY,15.00,18.00,12.00,16.00
5,Aggregate Base Course,3000,TON,35.00,40.00,32.00,38.00
6,Asphalt Binder Course,1500,TON,85.00,90.00,82.00,88.00
7,Asphalt Surface Course,1000,TON,100.00,105.00,95.00,102.00
8,Concrete Curb and Gutter,2500,LF,30.00,35.00,28.00,32.00
9,4-inch Concrete Sidewalk,1200,SY,45.00,50.00,42.00,48.00
10,Catch Basin Type 1,10,EA,2500.00,2800.00,2400.00,2600.00
11,18-inch RCP Storm Drain,800,LF,60.00,65.00,55.00,62.00
12,Thermoplastic Pavement Markings,5000,LF,2.00,2.50,1.80,2.20
13,Traffic Signs,20,EA,250.00,300.00,220.00,280.00
14,Sodding and Restoration,1500,SY,8.00,10.00,7.00,9.00
15,Erosion Control,1,LS,15000.00,18000.00,14000.00,16000.00
16,Construction Staking,1,LS,20000.00,25000.00,8000.00,22000.00
CSVEOF

chown ga:ga /home/ga/Documents/raw_bid_tabulation.csv

# Ensure WPS Spreadsheet is running and maximized
if ! pgrep -x "et" > /dev/null; then
    echo "Starting WPS Spreadsheet..."
    su - ga -c "DISPLAY=:1 et &"
    
    # Wait for window to appear
    for i in {1..20}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "wps"; then
            break
        fi
        sleep 1
    done
fi

# Maximize window (CRITICAL for agent visibility)
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "WPS Spreadsheets" 2>/dev/null || true

# Close any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="