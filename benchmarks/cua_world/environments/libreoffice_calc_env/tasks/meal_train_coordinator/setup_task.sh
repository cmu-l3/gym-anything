#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Meal Train Coordinator Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create meal train CSV with planted issues
cat > /home/ga/Documents/meal_train.csv << 'EOF'
Date,Volunteer Name,Meal Type,Dietary Notes,Delivery Time,Contact
2024-04-01,Sarah Johnson,Dinner,Vegetable lasagna,18:00,sarah@email.com
2024-04-02,Mike Chen,Dinner,Stir-fry tofu and vegetables,17:30,mike@email.com
2024-04-03,Emily Rodriguez,Lunch,Garden salad and soup,12:00,emily@email.com
2024-04-05,Jessica Lee,Dinner,Pasta primavera,18:30,jessica@email.com
2024-04-09,David Kim,Dinner,Bean and cheese burritos,17:00,david@email.com
2024-04-10,Amanda White,Breakfast,Muffins and fruit,09:00,amanda@email.com
2024-04-11,Robert Garcia,Dinner,Vegetarian chili,18:00,robert@email.com
2024-04-12,Linda Martinez,Dinner,Mushroom risotto,17:45,linda@email.com
2024-04-12,Tom Anderson,Dinner,Quinoa bowl,18:00,tom@email.com
2024-04-13,Karen Wilson,Lunch,Caprese sandwiches,12:30,karen@email.com
2024-04-14,James Brown,Dinner,Eggplant parmesan,18:15,james@email.com
2024-04-16,Patricia Davis,Dinner,Chicken noodle soup,17:30,patricia@email.com
2024-04-17,Christopher Taylor,Dinner,Veggie pizza,19:00,chris@email.com
2024-04-18,Mary Thomas,Breakfast,Pancakes and syrup,08:30,mary@email.com
2024-04-19,Daniel Moore,Dinner,Lentil curry,20:30,daniel@email.com
2024-04-21,Jennifer Jackson,Dinner,Stuffed bell peppers,17:30,jennifer@email.com
2024-04-23,Matthew Martin,Lunch,Greek salad,11:00,matthew@email.com
2024-04-25,Lisa Thompson,Dinner,Vegetable soup,18:00,lisa@email.com
EOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/meal_train.csv
sudo chmod 666 /home/ga/Documents/meal_train.csv

echo "✅ Created meal_train.csv with planted issues:"
echo "   - Gap: April 5 → April 9 (4 days)"
echo "   - Duplicate: April 12 (2 volunteers)"
echo "   - Dietary issue: Chicken soup (April 16)"
echo "   - Time issues: Deliveries at 11:00 AM, 8:30 PM, 9:00 PM"

# Launch LibreOffice Calc with the CSV
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/meal_train.csv > /tmp/calc_meal_train.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_meal_train.log || true
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

# Position cursor at beginning
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Meal Train Coordinator Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "   Sarah just had twins! Her friend Emily is coordinating a meal train."
echo "   The signup sheet has errors that need validation."
echo ""
echo "🎯 YOUR TASK:"
echo "   1. Add column to detect date GAPS (>2 days without meals)"
echo "   2. Add column to flag DUPLICATE dates (same day, multiple volunteers)"
echo "   3. Add column to check DIETARY compliance (family is vegetarian & nut-free)"
echo "   4. Add column to validate DELIVERY TIMES (prefer 5-7 PM for dinners)"
echo "   5. Calculate SUMMARY STATISTICS:"
echo "      - Total meals signed up"
echo "      - Date range coverage (days)"
echo "      - Number of problems found"
echo ""
echo "💡 HINTS:"
echo "   - Sort by date first (Data → Sort)"
echo "   - Use formulas like: COUNTIF, IF, SEARCH, date arithmetic"
echo "   - Known issues to find: April 5-9 gap, April 12 duplicate, chicken soup"
echo ""
echo "⏱️  You have 5 minutes. Good luck!"