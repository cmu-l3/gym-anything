#!/bin/bash
echo "=== Setting up usda_nutrition_menu_planner task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing files to ensure the agent creates them fresh
rm -f /home/ga/Documents/nutrition_analyzer.py 2>/dev/null || true
rm -f /home/ga/Documents/nutrition_report.txt 2>/dev/null || true

# Generate the USDA nutrition dataset
cat << 'EOF' > /home/ga/Documents/nutrition_data.csv
Food_Item,Calories_kcal,Protein_g,Iron_mg,Vitamin_C_mg
Spinach (raw),23,2.9,2.7,28.1
Lentils (raw),353,25.8,7.5,4.5
Chicken breast,165,31.0,1.0,0.0
Orange (raw),47,0.9,0.1,53.2
Broccoli (raw),34,2.8,0.7,89.2
Beef (ground 90% lean),176,20.0,2.6,0.0
Black beans (cooked),132,8.9,2.1,0.0
Bell pepper (red raw),31,1.0,0.4,127.7
Tofu (firm),144,15.8,2.7,0.0
Apple (raw),52,0.3,0.1,4.6
EOF

chown ga:ga /home/ga/Documents/nutrition_data.csv

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_ts
chmod 666 /tmp/task_start_ts

# Close any open activities to return to the Sugar home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Launch the Terminal activity for convenience, though agent can launch it itself
echo "Launching Terminal activity..."
su - ga -c "$SUGAR_ENV sugar-launch org.laptop.Terminal" &
sleep 5

# Verify Terminal is running
if pgrep -f "Terminal" > /dev/null 2>&1; then
    echo "Terminal activity is running"
else
    echo "WARNING: Terminal activity may not have started"
fi

# Take a verification screenshot of the initial state
su - ga -c "$SUGAR_ENV scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== usda_nutrition_menu_planner task setup complete ==="