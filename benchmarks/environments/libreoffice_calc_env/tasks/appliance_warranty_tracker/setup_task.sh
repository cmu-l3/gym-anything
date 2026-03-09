#!/bin/bash
# set -euo pipefail

echo "=== Setting up Appliance Warranty Tracker Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Create documents directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with appliance warranty data
cat > /home/ga/Documents/appliances_data.csv << 'EOF'
Appliance Name,Purchase Date,Warranty Months,Receipt Location,Manual Location
Refrigerator,2023-01-15,24,Filing Cabinet - Folder A,Kitchen Drawer
Dishwasher,2022-08-20,12,Digital - Google Drive,Utility Closet Shelf
Washing Machine,2024-03-10,36,Digital - Dropbox,Laundry Room Cabinet
Microwave,2021-11-05,12,Lost,Kitchen Drawer
Water Heater,2020-06-18,120,Basement Filing Box,Attached to Unit
EOF

# Set correct permissions
chown ga:ga /home/ga/Documents/appliances_data.csv
chmod 666 /home/ga/Documents/appliances_data.csv

echo "✅ Created appliances_data.csv with 5 appliance records"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/appliances_data.csv > /tmp/calc_warranty_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_warranty_task.log || true
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

# Position cursor at cell F1 to start working on new columns
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Appliance Warranty Tracker Task Setup Complete ==="
echo ""
echo "📋 Task Instructions:"
echo "  1. Create column F header: 'Warranty Expiration Date'"
echo "  2. In F2, enter formula: =EDATE(B2,C2) [or =DATE(YEAR(B2),MONTH(B2)+C2,DAY(B2))]"
echo "  3. Create column G header: 'Days Remaining'"
echo "  4. In G2, enter formula: =F2-TODAY()"
echo "  5. Create column H header: 'Status'"
echo "  6. In H2, enter formula: =IF(G2<0,\"Expired\",IF(G2<90,\"Expiring Soon\",\"Active\"))"
echo "  7. Copy formulas down to rows 3-6 for all appliances"
echo "  8. Select H2:H6 and apply conditional formatting:"
echo "     - Format → Conditional Formatting → Condition"
echo "     - Create rules for 'Expired' (red), 'Expiring Soon' (yellow), 'Active' (green)"
echo ""
echo "💡 Hints:"
echo "  - EDATE adds months to a date"
echo "  - TODAY() returns current date"
echo "  - Nested IF: IF(condition1, value1, IF(condition2, value2, value3))"
echo "  - Copy formulas: Select cell, Ctrl+C, select range, Ctrl+V"