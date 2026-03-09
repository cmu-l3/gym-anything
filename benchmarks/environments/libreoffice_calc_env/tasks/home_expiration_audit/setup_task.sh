#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Home Expiration Audit Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create messy CSV file with realistic inconsistent data
cat > /home/ga/Documents/home_inventory_messy.csv << 'CSVEOF'
Item Name,Location,Expiration Date,Status,Purchase Price,Category
aspirin 100ct,medicine cab,03/15/2024,kept,8.99,Meds
Ibuprofen 200mg,Medicine Cabinet,June 2024,kept,12.50,medication
BAND AIDS,first aid,12/01/2023,discarded,5.99,first aid
cinnamon,Pantry,Best by 08/2023,kept,4.50,spice
Vitamin D,medicine cab,09/30/2024,,15.99,Medicine
neosporin,First Aid Kit,11/2023,discarded,7.25,First Aid
black pepper,pantry,March 2025,kept,3.99,Spice
Tylenol PM,Med Cab,01/15/2024,kept,11.99,OTC
sunscreen SPF 50,Bathroom,07/31/2024,kept,13.99,personal care
hydrogen peroxide,medicine cabinet,10/15/2023,discarded,2.99,med
garlic powder,PANTRY,05/2023,discarded,3.50,Food
allergy pills,medicine cab,12/31/2024,kept,18.99,medication
contact solution,bathroom,Best by 02/2024,kept,9.99,Personal Care
gauze pads,first aid kit,No expiration,,6.50,First Aid
pasta sauce,pantry,11/30/2024,kept,4.99,food
multivitamin,Medicine Cabinet,08/15/2025,kept,22.99,Medicine
antibiotic oint,First Aid,04/2023,discarded,8.50,first aid
vanilla extract,Pantry,12/2025,kept,12.99,Food
hand sanitizer,bathroom,09/2024,kept,4.50,personal care
cough syrup,medicine cab,Best by 05/2024,kept,9.99,OTC
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/home_inventory_messy.csv
sudo chmod 666 /home/ga/Documents/home_inventory_messy.csv

echo "✅ Created messy inventory CSV with 20 items"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc with inventory file..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/home_inventory_messy.csv > /tmp/calc_audit_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_audit_task.log || true
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

# Ensure cursor is at A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Home Expiration Audit Task Setup Complete ==="
echo ""
echo "📋 Task Overview:"
echo "  You have a messy home inventory list with expired/expiring items"
echo ""
echo "🎯 Your Goals:"
echo "  1. Clean data: Standardize locations (Medicine Cabinet, Pantry, Bathroom, First Aid Kit)"
echo "  2. Clean data: Normalize categories (Medication, Food, Personal Care, First Aid)"
echo "  3. Parse dates: Convert all dates to MM/DD/YYYY format"
echo "  4. Add column: Days Until Expiration (=Expiration_Date - TODAY())"
echo "  5. Add column: Status Category (EXPIRED/URGENT/EXPIRING SOON/GOOD)"
echo "  6. Add column: Replacement Priority (1-4)"
echo "  7. Add column: Waste Flag (items discarded 180+ days after expiration)"
echo "  8. Apply conditional formatting: Red=expired, Orange=urgent, Yellow=expiring, Green=good"
echo "  9. Sort by: Priority (primary), Days Until Expiration (secondary)"
echo "  10. Create summary: Total items, expired count, waste cost, category analysis"
echo "  11. Save as: home_expiration_audit_cleaned.ods"
echo ""
echo "💡 Hints:"
echo "  - Use Find & Replace (Ctrl+H) for standardizing text"
echo "  - TRIM() removes spaces, PROPER() fixes capitalization"
echo "  - DATEVALUE() converts text dates to proper dates"
echo "  - TODAY() gives current date for calculations"
echo "  - Conditional Formatting: Format → Conditional Formatting"
echo "  - Multi-level sort: Data → Sort"