#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Quilting Fabric Calculator Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with pattern piece data (partial - agent must add calculation columns)
cat > /home/ga/Documents/fabric_template.csv << 'CSVEOF'
Pattern Piece,Length (in),Width (in),Quantity,Fabric Type,Fabric Width (in),Yards Purchased,Price per Yard,Area per Piece,Total Area,Area with Shrinkage,Yards Required,Additional Yards Needed,Additional Cost
Large Square,12.5,12.5,20,Blue Floral,44,1.5,12.99,,,,,,
Small Square,6.5,6.5,40,Yellow Solid,44,1.0,8.99,,,,,,
Rectangle,12.5,6.5,30,Green Print,44,2.0,11.99,,,,,,
Border Strip,72,4.5,4,Navy Solid,44,0.5,9.99,,,,,,
Backing,90,90,1,White Muslin,108,0,6.99,,,,,,
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/fabric_template.csv
sudo chmod 666 /home/ga/Documents/fabric_template.csv

echo "✅ Created fabric_template.csv"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/fabric_template.csv > /tmp/calc_fabric_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_fabric_task.log || true
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

# Position cursor at first empty calculation cell (Area per Piece column - I1 or thereabouts)
# Move to cell I2 (first data row, first calculation column)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
# Navigate to column I (Area per Piece)
for i in {1..8}; do
    safe_xdotool ga :1 key Right
    sleep 0.1
done
# Move down to data row
safe_xdotool ga :1 key Down
sleep 0.2

echo "=== Quilting Fabric Calculator Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "  Maria is planning a quilt and needs to calculate fabric requirements."
echo "  The spreadsheet shows pattern pieces with dimensions and existing purchases."
echo ""
echo "🎯 Your Goal:"
echo "  Complete the calculation columns (I through N) with formulas to:"
echo "  1. Calculate area per piece (Length × Width)"
echo "  2. Calculate total area needed (Area × Quantity)" 
echo "  3. Add 5% shrinkage (Total Area × 1.05)"
echo "  4. Convert to yards (Area / (Fabric Width × 36))"
echo "  5. Calculate additional yards needed (MAX(0, Required - Purchased))"
echo "  6. Calculate additional cost (Additional Yards × Price per Yard)"
echo "  7. Sum total additional cost at bottom"
echo ""
echo "💡 Key Points:"
echo "  - Fabric width constrains layout (pieces must fit across width)"
echo "  - Pre-washing causes 5% shrinkage"
echo "  - 1 yard = 36 inches"
echo "  - Can't buy negative yardage (use MAX function)"
echo ""
echo "📊 Expected Result:"
echo "  Total additional fabric cost should be approximately $30-50"