#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Appliance Replacement Advisor Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with realistic appliance inventory data
cat > /home/ga/Documents/appliance_inventory.csv << 'CSVEOF'
Appliance,Purchase Date,Expected Lifespan (years),Last Repair Cost,Current Repair Quote,Energy Use (kWh/year),Replacement Cost,Electricity Rate ($/kWh)
Refrigerator,2012-03-15,14,125,450,600,1200,0.12
HVAC System,2008-06-01,15,380,850,3500,4500,0.12
Washing Machine,2016-09-20,11,0,0,400,800,0.12
Dryer,2016-09-20,13,85,0,900,700,0.12
Dishwasher,2010-11-10,10,60,275,300,650,0.12
Water Heater,2014-02-28,12,0,0,4500,1100,0.12
Microwave,2019-05-15,9,0,0,200,250,0.12
Garbage Disposal,2011-07-04,12,40,120,50,200,0.12
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/appliance_inventory.csv
sudo chmod 666 /home/ga/Documents/appliance_inventory.csv

echo "✅ Created appliance inventory CSV with 8 appliances"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/appliance_inventory.csv > /tmp/calc_appliance_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_appliance_task.log || true
    # Don't exit, continue anyway
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
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

# Move cursor to first data row
echo "Positioning cursor..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
# Move to cell A2 (first data row)
safe_xdotool ga :1 key Down
sleep 0.2

echo "=== Appliance Replacement Advisor Task Setup Complete ==="
echo ""
echo "📋 TASK OVERVIEW:"
echo "Sarah needs help analyzing which appliances to repair vs. replace"
echo ""
echo "📝 REQUIRED CALCULATIONS:"
echo "  1. Calculate Age (years from purchase date)"
echo "  2. Calculate Age % of Lifespan"
echo "  3. Create Replacement Priority flags (HIGH/MEDIUM/LOW)"
echo "  4. Apply 50% Repair Rule (repair vs. replace recommendation)"
echo "  5. Calculate Annual Energy Cost"
echo "  6. Sort by priority or create urgency score"
echo ""
echo "💡 KEY FORMULAS:"
echo "  - Age: =YEAR(TODAY())-YEAR(B2)"
echo "  - Age %: =(Age/C2)*100"
echo "  - Priority: =IF(AgePercent>=80,\"HIGH\",IF(AgePercent>=60,\"MEDIUM\",\"LOW\"))"
echo "  - 50% Rule: =IF(E2/G2>0.5,\"NO - REPLACE\",\"YES - REPAIR\")"
echo "  - Energy Cost: =F2*\$H\$2"
echo ""
echo "🎯 GOAL: Help Sarah prioritize her home improvement budget"