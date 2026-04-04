#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Receipt Reconciliation Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create grocery receipt CSV with intentional errors
cat > /home/ga/Documents/grocery_receipt.csv << 'CSVEOF'
Item,Price
Organic Milk,5.49
Whole Grain Bread,3.99
Free Range Eggs,4.29
Bananas,2.17
Cherry Tomatoes,4.99
Greek Yogurt,6.99
Cherry Tomatoes,4.99
Pasta Sauce,3.79
Spaghetti,2.49
Olive Oil,8.99
Chicken Breast,12.78
Cheddar Cheese,5.99
Baby Spinach,3.49
Ground Coffee,11.99
Orange Juice,4.79
Granola Bars,5.49
Dish Soap,3.99
Paper Towels,7.99
Apples,4.29
Almonds,9.99
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/grocery_receipt.csv
sudo chmod 644 /home/ga/Documents/grocery_receipt.csv

echo "✅ Created grocery_receipt.csv with receipt data"

# Calculate expected values for logging
echo "📊 Expected values:"
echo "  - Number of items: 20 (with intentional errors)"
echo "  - Correct total: ~$119.67"
echo "  - Store charged: $127.43"
echo "  - Discrepancy: ~$7.76 (overcharge)"

# Launch LibreOffice Calc
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore > /tmp/calc_receipt_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_receipt_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
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

echo ""
echo "=== Receipt Reconciliation Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "  You just got home from grocery shopping."
echo "  The receipt shows a total of \$127.43"
echo "  Something feels wrong - it seems too high!"
echo ""
echo "🎯 YOUR TASK:"
echo "  1. Open 'grocery_receipt.csv' from Documents folder"
echo "     (File → Open → /home/ga/Documents/grocery_receipt.csv)"
echo "  2. Calculate actual total using SUM formula on all item prices"
echo "  3. Enter the store's charged amount: \$127.43"
echo "  4. Calculate the discrepancy (Charged - Calculated)"
echo "  5. Identify how much you were overcharged"
echo ""
echo "💡 HINT: Use =SUM(B2:B21) to add all prices"
echo "         Then subtract to find the difference"
echo ""
echo "📁 File ready: /home/ga/Documents/grocery_receipt.csv"
echo ""