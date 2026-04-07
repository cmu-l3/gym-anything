#!/bin/bash
echo "=== Setting up macronutrient_diet_calculator_pippy task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Clean up any pre-existing files
rm -f /home/ga/Documents/nutrition.csv 2>/dev/null || true
rm -f /home/ga/Documents/diet_report.txt 2>/dev/null || true
rm -f /home/ga/Documents/nutrition_calculator.py 2>/dev/null || true

# Generate the nutrition CSV file (Data is per 100g)
cat > /home/ga/Documents/nutrition.csv << 'EOF'
Food,Calories(kcal),Protein(g),Carbs(g),Fat(g)
Apple,52,0.3,13.8,0.2
Banana,89,1.1,22.8,0.3
Black Beans,132,8.9,23.7,0.5
Chicken Breast,165,31.0,0.0,3.6
Egg,143,12.6,0.7,9.5
Spinach,23,2.9,3.6,0.4
White Rice,130,2.7,28.2,0.3
Whole Milk,61,3.2,4.8,3.3
EOF

chown ga:ga /home/ga/Documents/nutrition.csv

# Record task start timestamp for mtime validation
date +%s > /tmp/diet_calculator_start_ts
chmod 666 /tmp/diet_calculator_start_ts

# Close any open activities to return to the Sugar home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Ensure Sugar home view is visible
if ! pgrep -f "jarabe.main" > /dev/null 2>&1; then
    echo "Sugar session not found, restarting..."
    systemctl restart gdm 2>/dev/null || true
    sleep 15
fi

# Take a verification screenshot of the initial state
su - ga -c "$SUGAR_ENV scrot /tmp/diet_task_start.png" 2>/dev/null || true

echo "=== setup complete ==="
echo "nutrition.csv is ready. Agent must use Pippy to calculate totals and create diet_report.txt"