#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Appliance Price Tracker Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with 8 weeks of price tracking data (4 retailers × 8 weeks = 32 rows)
cat > /home/ga/Documents/dishwasher_prices.csv << 'EOF'
Week,Date,Retailer,Base_Price,Delivery_Fee,Rebate
1,2024-01-07,Home Depot,899.00,79.99,0.00
1,2024-01-07,Lowes,879.00,89.99,25.00
1,2024-01-07,Best Buy,929.00,0.00,0.00
1,2024-01-07,Costco,849.00,59.99,0.00
2,2024-01-14,Home Depot,899.00,79.99,0.00
2,2024-01-14,Lowes,879.00,89.99,0.00
2,2024-01-14,Best Buy,899.00,49.99,0.00
2,2024-01-14,Costco,849.00,59.99,0.00
3,2024-01-21,Home Depot,849.00,79.99,50.00
3,2024-01-21,Lowes,899.00,89.99,0.00
3,2024-01-21,Best Buy,879.00,0.00,0.00
3,2024-01-21,Costco,829.00,59.99,0.00
4,2024-01-28,Home Depot,899.00,0.00,0.00
4,2024-01-28,Lowes,859.00,89.99,50.00
4,2024-01-28,Best Buy,899.00,49.99,25.00
4,2024-01-28,Costco,849.00,59.99,0.00
5,2024-02-04,Home Depot,879.00,79.99,0.00
5,2024-02-04,Lowes,879.00,89.99,25.00
5,2024-02-04,Best Buy,929.00,0.00,0.00
5,2024-02-04,Costco,819.00,59.99,0.00
6,2024-02-11,Home Depot,899.00,79.99,25.00
6,2024-02-11,Lowes,899.00,89.99,0.00
6,2024-02-11,Best Buy,899.00,0.00,0.00
6,2024-02-11,Costco,849.00,59.99,0.00
7,2024-02-18,Home Depot,879.00,79.99,50.00
7,2024-02-18,Lowes,889.00,89.99,75.00
7,2024-02-18,Best Buy,899.00,49.99,50.00
7,2024-02-18,Costco,839.00,59.99,0.00
8,2024-02-25,Home Depot,849.00,0.00,50.00
8,2024-02-25,Lowes,859.00,89.99,75.00
8,2024-02-25,Best Buy,879.00,0.00,25.00
8,2024-02-25,Costco,829.00,59.99,0.00
EOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/dishwasher_prices.csv
sudo chmod 644 /home/ga/Documents/dishwasher_prices.csv

echo "✅ Created dishwasher_prices.csv with 32 rows of price data"

# Launch LibreOffice Calc with the CSV
echo "Launching LibreOffice Calc with price tracking data..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/dishwasher_prices.csv > /tmp/calc_tracker_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_tracker_task.log || true
    # Continue anyway
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Continue anyway
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
        echo "✅ Calc window focused"
        # Maximize window
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

# Position cursor at cell G1 (where Total Cost column should be added)
echo "Positioning cursor..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
# Move to column G
safe_xdotool ga :1 key --repeat 6 Right
sleep 0.3

echo "=== Appliance Price Tracker Task Setup Complete ==="
echo ""
echo "📊 Scenario: Sarah has tracked dishwasher prices for 8 weeks across 4 retailers"
echo "📝 Your Tasks:"
echo "  1. Create 'Total Cost' column (G): =(Base_Price * 1.07) + Delivery_Fee - Rebate"
echo "  2. Apply formula to all 32 data rows (rows 2-33)"
echo "  3. Identify best historical price per retailer (use MIN/MINIFS)"
echo "  4. Find current best deal in Week 8 (rows 29-32)"
echo "  5. Count how many weeks each retailer had the lowest price"
echo ""
echo "💡 Hints:"
echo "  - 7% sales tax = multiply base price by 1.07"
echo "  - MINIFS syntax: =MINIFS(\$G:\$G, \$C:\$C, \"Retailer Name\")"
echo "  - Week 8 is the last 4 rows of data"