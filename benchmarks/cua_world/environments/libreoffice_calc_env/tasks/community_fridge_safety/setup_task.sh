#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Community Fridge Safety Manager Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Calculate dates relative to today for realistic scenario
# We'll create items that are:
# - Already expired (negative days)
# - Expiring in 1-2 days (critical - red)
# - Expiring in 4-6 days (warning - yellow)  
# - Expiring in 10+ days (safe - no color)

# Create CSV with community fridge inventory data
cat > /home/ga/Documents/community_fridge_inventory.csv << 'EOF'
Item Name,Donation Date,Expiration Date,Volunteer Name
Milk - 2%,2024-01-15,2024-01-20,Sarah
Yogurt - Strawberry,2024-01-18,2024-01-22,Mike
Lettuce - Romaine,2024-01-19,2024-01-21,Sarah
Cheese - Cheddar,2024-01-10,2024-02-10,Alex
Bread - Whole Wheat,2024-01-20,2024-01-23,Jordan
Eggs - Dozen,2024-01-17,2024-02-07,Sarah
Apples - Gala,2024-01-16,2024-01-30,Mike
Carrots - 2lb bag,2024-01-19,2024-02-02,Alex
Orange Juice,2024-01-18,2024-01-24,Jordan
Butter,2024-01-14,2024-02-28,Sarah
Tofu,2024-01-20,2024-01-27,Mike
Sour Cream,2024-01-19,2024-01-26,Alex
Spinach,2024-01-20,2024-01-22,Jordan
Chicken Breast,2024-01-19,2024-01-21,Sarah
Cream Cheese,2024-01-15,2024-02-15,Mike
Hummus,2024-01-21,2024-01-25,Alex
Bell Peppers,2024-01-20,2024-01-28,Jordan
Ground Beef,2024-01-21,2024-01-24,Sarah
EOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/community_fridge_inventory.csv
sudo chmod 666 /home/ga/Documents/community_fridge_inventory.csv

echo "✅ Created community_fridge_inventory.csv"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/community_fridge_inventory.csv > /tmp/calc_fridge_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_fridge_task.log || true
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

echo "=== Community Fridge Safety Manager Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Insert column E with header 'Days Until Expiration'"
echo "  2. In E2, enter formula: =C2-TODAY()"
echo "  3. Copy formula down to all data rows"
echo "  4. Select column E data range (E2:E19)"
echo "  5. Apply conditional formatting:"
echo "     - Format → Conditional Formatting → Condition"
echo "     - Rule 1: Cell value ≤ 3 → RED background, white text"
echo "     - Rule 2: Cell value > 3 AND ≤ 7 → YELLOW background"
echo "  6. Select all data (A1:E19)"
echo "  7. Sort by column E (Data → Sort) - ascending order"
echo "  8. Save as: community_fridge_sorted.ods"