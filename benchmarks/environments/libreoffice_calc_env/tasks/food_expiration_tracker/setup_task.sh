#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Food Expiration Tracker Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with food inventory data
cat > /home/ga/Documents/food_inventory.csv << 'EOF'
Item Name,Category,Purchase Date,Shelf Life Days,Expiration Date,Days Until Expiration
Milk,Dairy,2024-12-10,7,,
Yogurt,Dairy,2024-12-08,14,,
Cheese,Dairy,2024-12-01,30,,
Bread,Bakery,2024-12-11,5,,
Apples,Produce,2024-12-10,14,,
Bananas,Produce,2024-12-10,7,,
Carrots,Produce,2024-12-08,21,,
Chicken Breast,Meat,2024-12-13,3,,
Ground Beef,Meat,2024-12-14,2,,
Canned Tomatoes,Canned Goods,2023-12-01,730,,
Canned Beans,Canned Goods,2024-01-01,730,,
Pasta,Pantry,2024-03-01,730,,
Rice,Pantry,2024-06-01,365,,
Flour,Pantry,2024-08-01,180,,
Olive Oil,Pantry,2024-05-01,365,,
Eggs,Dairy,2024-12-05,21,,
Butter,Dairy,2024-12-05,30,,
Lettuce,Produce,2024-12-12,7,,
Tomatoes,Produce,2024-12-11,7,,
Orange Juice,Beverages,2024-12-13,7,,
EOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/food_inventory.csv
sudo chmod 666 /home/ga/Documents/food_inventory.csv

echo "✅ Created food_inventory.csv with 20 food items"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc with food inventory..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/food_inventory.csv > /tmp/calc_food_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_food_task.log
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
        # Maximize window
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

# Move cursor to cell E2 (first empty cell for Expiration Date)
echo "Positioning cursor at cell E2..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key Right Right Right Right Down
sleep 0.3

echo "=== Food Expiration Tracker Task Setup Complete ==="
echo ""
echo "📋 Task Instructions:"
echo "  1. In cell E2, enter formula: =C2+D2 (Purchase Date + Shelf Life)"
echo "  2. Copy formula E2 down to all rows (E2:E21)"
echo "  3. In cell F2, enter formula: =E2-TODAY() (Days Until Expiration)"
echo "  4. Copy formula F2 down to all rows (F2:F21)"
echo "  5. Select column F data (F2:F21)"
echo "  6. Apply conditional formatting: Format → Conditional Formatting → Condition"
echo "     - Condition: Cell value ≤ 7"
echo "     - Format: Bold, red/orange background"
echo "  7. Select all data (A1:F21)"
echo "  8. Sort by Days Until Expiration: Data → Sort"
echo "     - Sort by: Column F (Days Until Expiration)"
echo "     - Order: Ascending"
echo ""
echo "💡 Goal: Create an actionable food waste prevention tracker!"