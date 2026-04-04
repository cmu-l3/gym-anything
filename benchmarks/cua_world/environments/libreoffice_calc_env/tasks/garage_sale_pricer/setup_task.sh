#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Garage Sale Pricing Strategy Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV file with realistic garage sale inventory
cat > /home/ga/Documents/garage_sale_items.csv << 'CSVEOF'
Item Name,Category,Original Price,Condition,Market Research Price,Notes
Leather Sofa 3-Seater,Furniture,1200,Good,400,Small tear on left armrest
Dell Laptop i5 8GB,Electronics,800,Excellent,350,2 years old - works perfectly
Dining Table Set Oak,Furniture,600,Fair,150,Seats 6 - some scratches on surface
KitchenAid Stand Mixer,Appliances,300,Excellent,180,Barely used - red color
Mountain Bike 21-Speed,Sports Equipment,450,Good,200,Needs new tires
Microwave 1100W,Appliances,120,Good,50,Works well - minor rust inside
Bookshelf 5-Tier Wood,Furniture,180,Fair,60,Sturdy but needs refinishing
Samsung Smart TV 42",Electronics,600,Good,280,Minor backlight issue
Coffee Maker Programmable,Kitchen Items,80,Excellent,35,Used less than 10 times
Running Shoes Nike Size 10,Clothing,120,Excellent,40,Worn twice - too small
Floor Lamp Modern,Decor,90,Good,30,Brass finish - one bulb socket loose
Vacuum Dyson Upright,Appliances,400,Good,180,Strong suction - some scratches
Pots and Pans Set 10pc,Kitchen Items,150,Fair,45,Non-stick wearing off
Gaming Console Xbox,Electronics,300,Excellent,220,Includes 2 controllers
Dresser 6-Drawer Pine,Furniture,350,Fair,100,Solid wood - needs paint
Tent 4-Person Camping,Sports Equipment,200,Good,80,Used 3 times - small stain
Wall Mirror Decorative,Decor,110,Excellent,50,Ornate gold frame
Toaster Oven Large,Kitchen Items,90,Good,35,Works perfectly - exterior scratched
Winter Jacket Columbia,Clothing,180,Good,60,Men's Large - slight pilling
Office Chair Ergonomic,Furniture,280,Good,120,Mesh back - all adjustments work
Blender Vitamix,Appliances,350,Excellent,200,Powerful - like new condition
Table Lamp Ceramic Base,Decor,45,Fair,15,Shade has small tear
Weights Dumbbell Set,Sports Equipment,180,Excellent,90,5-25 lbs pairs - barely used
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/garage_sale_items.csv
sudo chmod 666 /home/ga/Documents/garage_sale_items.csv

echo "✅ Created garage_sale_items.csv with 23 items"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/garage_sale_items.csv > /tmp/calc_garage_sale.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_garage_sale.log || true
    # exit 1
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # exit 1
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

# Position cursor at first empty column (column G - Base Price)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Garage Sale Pricing Strategy Task Setup Complete ==="
echo ""
echo "📋 TASK INSTRUCTIONS:"
echo "════════════════════════════════════════════════════════════"
echo "You have a CSV file with 23 garage sale items to price."
echo ""
echo "STEP 1: Create 'Base Price' formula in column G"
echo "  - G1: Type header 'Base Price'"
echo "  - G2: Create formula based on condition (column D):"
echo "        Excellent → 80% of Market Research Price (column E)"
echo "        Good → 65% of Market Research Price"
echo "        Fair → 45% of Market Research Price"
echo "  - Copy formula down to all rows"
echo ""
echo "STEP 2: Create 'Quick Sale?' flag in column H"
echo "  - H1: Type header 'Quick Sale?'"
echo "  - H2: Check if category (column B) is 'Furniture' or 'Appliances'"
echo "        Mark 'Yes' if true, 'No' if false"
echo "  - Copy down to all rows"
echo ""
echo "STEP 3: Create 'Final Sale Price' in column I"
echo "  - I1: Type header 'Final Sale Price'"
echo "  - I2: If Quick Sale='Yes', apply 20% discount to Base Price"
echo "        Otherwise use Base Price as-is"
echo "  - Ensure no price goes below \$1.00"
echo "  - Copy down to all rows"
echo ""
echo "STEP 4: Calculate Total Revenue"
echo "  - At bottom of column I, add SUM formula"
echo "  - Label it 'TOTAL PROJECTED REVENUE'"
echo ""
echo "STEP 5: Format as currency"
echo "  - Select columns G, I (Base Price and Final Sale Price)"
echo "  - Apply currency format with \$ symbol"
echo ""
echo "STEP 6: Save as ODS"
echo "  - File → Save As → garage_sale_pricing.ods"
echo "════════════════════════════════════════════════════════════"