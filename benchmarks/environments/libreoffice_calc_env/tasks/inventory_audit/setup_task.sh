#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Inventory Audit Reconciliation Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with realistic inventory data (45 items)
cat > /home/ga/Documents/inventory_data.csv << 'CSVEOF'
Product Name,Expected Qty,Actual Count,Unit Price
Wireless Mouse,45,42,24.99
USB-C Cable 6ft,120,122,8.99
Laptop Stand,28,25,34.95
Bluetooth Keyboard,35,35,45.50
HDMI Cable,88,85,12.75
Webcam HD 1080p,15,13,59.99
Phone Charger,150,148,9.99
Screen Protector,200,195,4.99
Laptop Sleeve 15in,32,30,19.99
USB Flash Drive 32GB,75,78,11.50
Ethernet Cable 10ft,60,60,7.25
Portable Hard Drive 1TB,22,19,79.99
Wireless Earbuds,18,15,89.99
Phone Case,95,92,14.95
Laptop Charger,25,23,42.50
SD Card 64GB,110,108,15.75
Monitor 24in,12,12,149.99
Desk Lamp LED,40,38,29.99
Surge Protector,55,57,22.50
Cable Organizer,85,85,6.99
Laptop Cooling Pad,20,18,25.50
Wireless Router,14,13,68.99
USB Hub 4-Port,48,50,16.99
Gaming Mouse,30,27,54.99
Mechanical Keyboard,18,18,79.95
Phone Holder,72,70,12.25
Webcam Privacy Cover,180,175,2.99
Screen Cleaning Kit,65,65,8.50
Tablet Stand,38,35,18.75
Stylus Pen,52,55,11.99
USB Adapter,95,92,5.75
Power Bank 20000mAh,25,22,45.99
Laptop Bag,28,28,39.95
Wireless Presenter,16,14,32.50
Document Scanner,8,7,129.99
Label Maker,12,12,44.95
Desk Organizer,42,40,15.50
Printer Paper Ream,88,85,6.25
Ink Cartridge Black,45,42,28.99
Ink Cartridge Color,38,35,34.99
Stapler,55,55,9.75
Tape Dispenser,70,68,5.50
Scissors,48,50,4.25
Pen Set,125,120,8.99
Notebook Pack,90,88,12.50
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/inventory_data.csv

echo "✅ Created inventory data CSV with 45 items"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/inventory_data.csv > /tmp/calc_inventory_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_inventory_task.log || true
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

# Position cursor at cell E2 (first cell where agent needs to add formula)
echo "Positioning cursor at cell E2..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key Right Right Right Right
sleep 0.2
safe_xdotool ga :1 key Down
sleep 0.2

echo "=== Inventory Audit Task Setup Complete ==="
echo ""
echo "📊 TASK INSTRUCTIONS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "SCENARIO: Store manager needs to reconcile inventory after physical count"
echo ""
echo "STEP 1: Calculate Differences (Column E)"
echo "  • Click cell E2"
echo "  • Enter formula: =C2-B2"
echo "  • Copy formula down to E46"
echo ""
echo "STEP 2: Calculate Value Impact (Column F)"
echo "  • Click cell F2"
echo "  • Enter formula: =E2*D2"
echo "  • Copy formula down to F46"
echo ""
echo "STEP 3: Apply Conditional Formatting to Differences"
echo "  • Select range E2:E46"
echo "  • Format → Conditional Formatting → Condition"
echo "  • Rule 1: If < 0, red background (shortages)"
echo "  • Rule 2: If > 0, yellow background (overages)"
echo ""
echo "STEP 4: Apply Conditional Formatting to Value Impact"
echo "  • Select range F2:F46"
echo "  • Format → Conditional Formatting → Condition"
echo "  • Highlight large negative values (e.g., < -50)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"