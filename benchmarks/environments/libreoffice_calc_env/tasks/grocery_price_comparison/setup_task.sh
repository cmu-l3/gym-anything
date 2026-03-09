#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Grocery Price Comparison Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with messy grocery data from three stores
cat > /home/ga/Documents/grocery_data.csv << 'EOF'
Store A Product,Store A Qty (oz/ct),Store A Price ($),Store B Product,Store B Qty (oz/ct),Store B Price ($),Store C Product,Store C Qty (oz/ct),Store C Price ($)
Milk 1gal,128,3.99,MILK WHOLE 1GAL,128,4.29,milk whole,128,3.79
Eggs Dozen,12,2.89,EGGS 12CT,12,3.19,eggs large,12,2.69
Bread Wheat 24oz,24,2.49,WHEAT BREAD 24oz,24,2.79,bread whole wheat,24,2.29
Butter 1lb,16,4.99,BUTTER UNSALTED 1LB,16,5.49,butter 16oz,16,4.79
Coffee Ground 12oz,12,7.99,COFFEE GROUND 12OZ,12,8.49,,0,
Orange Juice 64oz,64,4.49,OJ 64oz,64,3.99,orange juice 64oz,64,4.29
Cereal 18oz,18,3.99,CEREAL CORN FLAKES 18oz,18,4.29,cereal 18oz,18,3.79
Yogurt 32oz,32,3.49,YOGURT PLAIN 32OZ,32,3.99,yogurt greek 32oz,32,3.29
Chicken Breast 1lb,16,5.99,CHICKEN BREAST /LB,16,6.49,chicken breast,16,5.79
Ground Beef 1lb,16,4.99,BEEF GROUND 80/20,16,5.29,ground beef 1lb,16,4.79
Pasta 16oz,16,1.29,PASTA PENNE 16OZ,16,1.49,pasta 1lb,16,1.19
Tomato Sauce 24oz,24,1.99,SAUCE MARINARA 24oz,24,2.29,,0,
Cheese Cheddar 8oz,8,3.99,CHEDDAR CHEESE 8OZ,8,4.49,cheese cheddar 8oz,8,3.79
Rice 32oz,32,2.99,RICE WHITE 2LB,32,3.29,white rice 32oz,32,2.79
Bananas 1lb,16,0.59,BANANAS /LB,16,0.69,bananas per lb,16,0.49
Apples 3lb,48,3.99,APPLES GALA 3LB,48,4.49,apples 3lb bag,48,3.79
Lettuce Head,1,1.99,LETTUCE ROMAINE HEAD,1,2.29,romaine lettuce,1,1.79
Carrots 2lb,32,1.99,CARROTS 2LB BAG,32,2.29,carrots 2lb,32,1.79
Potatoes 5lb,80,3.99,POTATOES RUSSET 5LB,80,4.49,russet potatoes 5lb,80,3.79
Onions 3lb,48,2.49,ONIONS YELLOW 3LB,48,2.79,,0,
Paper Towels 6ct,6,8.99,PAPER TOWELS 6 ROLL,6,9.49,paper towels 6pk,6,8.49
Dish Soap 24oz,24,2.99,DISH SOAP 24OZ,24,3.29,dish soap,24,2.79
Laundry Det 100oz,100,11.99,LAUNDRY DETERGENT 100OZ,100,12.99,laundry soap 100oz,100,11.49
Trash Bags 30ct,30,7.99,TRASH BAGS 30CT 13GAL,30,8.49,trash bags 30,30,7.49
EOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/grocery_data.csv
sudo chmod 666 /home/ga/Documents/grocery_data.csv

echo "✅ Created grocery_data.csv with messy data from 3 stores"

# Launch LibreOffice Calc with the CSV
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/grocery_data.csv > /tmp/calc_grocery_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_grocery_task.log || true
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

echo "=== Grocery Price Comparison Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Standardize product names (currently inconsistent across stores)"
echo "  2. Calculate unit prices: =Price/Quantity for each store"
echo "  3. Find minimum price: =MIN(unit_price_A, unit_price_B, unit_price_C)"
echo "  4. Generate recommendations: Use IF() to identify cheapest store"
echo "  5. Apply conditional formatting to highlight best prices"
echo "  6. Calculate summary statistics (total savings, store comparison)"
echo ""
echo "💡 Tip: Some stores don't carry all items (empty cells). Handle these in formulas!"