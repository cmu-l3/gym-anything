#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Paint Inventory Calculator Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with partial/messy room data
cat > /home/ga/Documents/paint_rooms.csv << 'EOF'
Room Name,Length_ft,Width_ft,Ceiling_ft,Doors,Windows,Paint Color,Notes
Living Room,18,15,9,2,3,Agreeable Gray,Bought 2 gallons already
Master Bedroom,14,12,,1,2,Sea Salt,$35/gal at HomeDepot
Kitchen,12,10,8,3,1,Pure White,Need 2 coats
Guest Bedroom,11,10,,1,1,Sea Salt,Same as master
Hallway,20,4,8,2,0,Pure White,Long narrow
Bathroom,8,6,8,1,1,Sea Salt,Small space
Dining Room,13,12,9,1,2,Agreeable Gray,$32/gal
Office,10,10,,1,2,Coastal Blue,$38/gal new color

Coverage: 375 sq ft/gallon | Standard deductions: Door=20sqft Window=15sqft | Tax rate: 7%
Most rooms need 2 coats. Pure White is cheaper at $28/gal
EOF

chown ga:ga /home/ga/Documents/paint_rooms.csv
chmod 644 /home/ga/Documents/paint_rooms.csv

echo "✅ Created paint_rooms.csv with partial data"
ls -lh /home/ga/Documents/paint_rooms.csv

# Launch LibreOffice Calc with the CSV
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/paint_rooms.csv > /tmp/calc_paint_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_paint_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice" 90; then
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

# Move cursor to first data cell (A2)
safe_xdotool ga :1 key ctrl+Home
sleep 0.2
safe_xdotool ga :1 key Down
sleep 0.2

echo "=== Paint Inventory Calculator Task Setup Complete ==="
echo ""
echo "🏠 SCENARIO: Home renovation paint calculation emergency!"
echo "📋 The homeowner needs to calculate paint quantities BEFORE the store closes"
echo ""
echo "📝 YOUR TASKS:"
echo "  1. Fill missing ceiling heights (use 8 ft where blank)"
echo "  2. Calculate wall area: Perimeter × Height - Door/Window deductions"
echo "  3. Calculate paint needed with ROUNDUP (coverage: 375 sq ft/gal, 2 coats)"
echo "  4. Calculate costs (Agreeable Gray: \$32, Sea Salt: \$35, Pure White: \$28, Coastal Blue: \$38)"
echo "  5. Sum total cost and add 7% tax"
echo ""
echo "💡 KEY FORMULA HINTS:"
echo "  - Wall Area: =2*(Length+Width)*Height-(Doors*20)-(Windows*15)"
echo "  - Paint Gallons: =ROUNDUP(Total_Area*2/375, 0)  [2 coats, 375 coverage]"
echo "  - Cost: =Gallons*PricePerGallon"
echo "  - Total with Tax: =SUM(costs)*1.07"
echo ""
echo "⚠️  REMEMBER: Can't buy 2.3 gallons - must ROUNDUP to whole numbers!"