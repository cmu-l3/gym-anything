#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Meal Rotation Tracker Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Generate meal log CSV with 60 days of realistic data
# Use Python to generate dates going back 60 days
python3 << 'PYEOF'
from datetime import datetime, timedelta
import random
import csv

# Common dinner meals with realistic repetition patterns
meals = [
    "Spaghetti", "Tacos", "Chicken Stir-fry", "Pizza", "Grilled Salmon",
    "Beef Chili", "Roast Chicken", "Burgers", "Lasagna", "Pork Chops",
    "Fish and Chips", "Pasta Primavera", "Beef Stew", "Chicken Curry",
    "Quesadillas", "Meatloaf", "Shepherd's Pie", "Grilled Chicken",
    "Teriyaki Salmon", "Vegetable Stir-fry"
]

# Generate 60 days of meal data
meal_log = []
end_date = datetime.now()
start_date = end_date - timedelta(days=59)

# Create a weighted distribution (some meals more common than others)
meal_weights = {}
for meal in meals:
    meal_weights[meal] = random.randint(1, 10)

current_date = start_date
for day in range(60):
    date_str = current_date.strftime("%Y-%m-%d")
    
    # Pick a meal with weighted random selection
    selected_meal = random.choices(
        list(meal_weights.keys()),
        weights=list(meal_weights.values()),
        k=1
    )[0]
    
    meal_log.append([date_str, selected_meal])
    current_date += timedelta(days=1)

# Write to CSV
with open('/home/ga/Documents/meal_log.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['Date', 'Meal'])
    writer.writerows(meal_log)

print("Generated 60 days of meal log data")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/meal_log.csv
sudo chmod 666 /home/ga/Documents/meal_log.csv

echo "✅ Created meal_log.csv with 60 days of data"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/meal_log.csv > /tmp/calc_meal_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_meal_task.log || true
    # Don't exit, continue for robustness
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit, continue for robustness
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

echo "=== Meal Rotation Tracker Task Setup Complete ==="
echo "📊 Meal log loaded with 60 days of dinner data"
echo ""
echo "📝 Task Instructions:"
echo "  1. Review the meal log in columns A (Date) and B (Meal)"
echo "  2. Create a summary section (e.g., starting at E2)"
echo "  3. List 5-8 common meals in a column"
echo "  4. Add 'Days Since Last Eaten' column with formula: =TODAY() - MAXIFS(\$A:\$A, \$B:\$B, E3)"
echo "  5. Add 'Times Eaten' column with formula: =COUNTIF(\$B:\$B, E3)"
echo "  6. Apply conditional formatting to 'Days Since' column:"
echo "     - Green for ≥21 days (overdue, good to make)"
echo "     - Red for ≤7 days (recently eaten, avoid)"
echo "  7. Save the file"
echo ""
echo "💡 Tip: Use Format → Conditional Formatting → Condition"