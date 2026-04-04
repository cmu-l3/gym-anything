#!/bin/bash
# set -euo pipefail

echo "=== Setting up Meal Kit Value Calculator Task ==="

source /workspace/scripts/task_utils.sh

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with meal comparison data
cat > /home/ga/Documents/meal_comparison_data.csv << 'CSVEOF'
Source,Date,Meal_Name,Total_Cost,Servings,Waste_Percent,Notes
MealKit,2024-01-05,Chicken Teriyaki,11.99,2,0.05,Perfectly portioned
MealKit,2024-01-07,Beef Tacos,13.49,2,0.05,Pre-measured spices
MealKit,2024-01-10,Salmon Rice Bowl,14.99,2,0.08,Fresh herbs included
MealKit,2024-01-12,Pasta Carbonara,10.99,2,0.05,Exact portions
MealKit,2024-01-14,Thai Curry,12.99,2,0.07,All ingredients used
MealKit,2024-01-17,Steak Fajitas,15.99,2,0.05,Premium cut
Grocery,2024-01-20,Chicken Teriyaki,8.47,2,0.30,Bought full cilantro bunch
Grocery,2024-01-22,Beef Tacos,9.23,2,0.25,Leftover taco shells went stale
Grocery,2024-01-24,Salmon Rice Bowl,12.18,2,0.22,Half the herbs wasted
Grocery,2024-01-26,Pasta Carbonara,7.85,2,0.18,Already had some pantry items
Grocery,2024-01-28,Thai Curry,10.34,2,0.35,Bought large spice containers
Grocery,2024-01-30,Steak Fajitas,13.67,2,0.28,Peppers partially used
Subscription,Monthly,Subscription Fee,9.99,,,Monthly service fee
CSVEOF

chown ga:ga /home/ga/Documents/meal_comparison_data.csv
echo "✅ Created meal_comparison_data.csv with 12 meals + subscription info"

# Launch LibreOffice Calc with the CSV
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/meal_comparison_data.csv > /tmp/calc_meal_kit.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_meal_kit.log || true
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

# Position cursor at first data cell
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Meal Kit Value Calculator Task Setup Complete ==="
echo ""
echo "📊 Data loaded: 6 meal kit meals vs 6 grocery meals"
echo ""
echo "📝 Task Instructions:"
echo "  1. Calculate per-serving costs (Total Cost / Servings)"
echo "  2. Adjust grocery costs for food waste: Cost / (1 - Waste%)"
echo "  3. Calculate waste-adjusted per-serving costs"
echo "  4. Use AVERAGE() to find mean cost for meal kits and grocery"
echo "  5. Factor in subscription fee ($9.99/month across all meal kit servings)"
echo "  6. Calculate cost difference (absolute $ and %)"
echo "  7. Format as currency and percentages"
echo ""
echo "💡 Hints:"
echo "  - Waste adjustment: =D2/(1-F2) for grocery, =D2 for meal kit"
echo "  - Subscription fee is in row 13"
echo "  - Create summary section around row 15-20"
echo "  - Format currency: Ctrl+1 → Currency"
echo ""
echo "🎯 Goal: Determine if meal kits are worth the premium vs grocery shopping"