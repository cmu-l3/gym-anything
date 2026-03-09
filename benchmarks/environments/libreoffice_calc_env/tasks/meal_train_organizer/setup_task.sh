#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Meal Train Organizer Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create meal train CSV with intentional conflicts
cat > /home/ga/Documents/meal_train_signups.csv << 'CSVEOF'
Date,Volunteer_Name,Dish_Planned,Contains_Meat,Contact_Info
2025-03-01,Jennifer Lee,Vegetable Lasagna,No,jlee@email.com
2025-03-02,Michael Chen,Spinach Quiche,No,mchen@email.com
2025-03-03,Sarah Johnson,Mushroom Risotto,No,sjohnson@email.com
2025-03-03,David Park,Pasta Primavera,No,dpark@email.com
2025-03-04,Emily Rodriguez,Bean Burrito Bowl,No,erodriguez@email.com
2025-03-05,Robert Miller,Meatloaf,Yes,rmiller@email.com
2025-03-06,Amanda Wilson,Vegetable Curry,No,awilson@email.com
2025-03-08,Lisa Thompson,Caprese Salad Platter,No,lthompson@email.com
2025-03-09,James Anderson,BBQ Chicken,Yes,janderson@email.com
2025-03-11,Patricia Brown,Eggplant Parmesan,No,pbrown@email.com
2025-03-11,Kevin Martinez,Cheese Enchiladas,No,kmartinez@email.com
2025-03-12,Nancy Davis,Vegetable Stir Fry,No,ndavis@email.com
2025-03-13,Christopher Garcia,Tomato Soup & Grilled Cheese,No,cgarcia@email.com
2025-03-14,Michelle Thomas,Greek Salad with Falafel,No,mthomas@email.com
CSVEOF

# Set proper ownership
sudo chown ga:ga /home/ga/Documents/meal_train_signups.csv
sudo chmod 666 /home/ga/Documents/meal_train_signups.csv

echo "✅ Created meal_train_signups.csv with conflicts:"
echo "   - Duplicate dates: March 3 (2 signups), March 11 (2 signups)"
echo "   - Missing dates: March 7, March 10"
echo "   - Dietary violations: March 5 (Meatloaf), March 9 (BBQ Chicken)"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/meal_train_signups.csv > /tmp/calc_meal_train.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_meal_train.log
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

# Position cursor at the beginning
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Meal Train Organizer Task Setup Complete ==="
echo ""
echo "📋 TASK: Resolve meal train conflicts for Sarah's recovery"
echo "🗓️  Period: March 1-14, 2025 (14 consecutive days)"
echo "🥗 Requirement: ALL vegetarian meals (no meat)"
echo ""
echo "⚠️  PROBLEMS TO SOLVE:"
echo "   1. Duplicate dates (March 3, March 11) - multiple signups"
echo "   2. Missing dates (March 7, March 10) - no coverage"
echo "   3. Dietary violations (March 5, March 9) - contain meat"
echo ""
echo "💡 HINTS:"
echo "   - Add columns to flag conflicts and dietary issues"
echo "   - Use COUNTIF to detect duplicates"
echo "   - Check all 14 dates have exactly one vegetarian meal"
echo "   - Reassign duplicate volunteers to gap dates"
echo "   - Add summary statistics at top or bottom"