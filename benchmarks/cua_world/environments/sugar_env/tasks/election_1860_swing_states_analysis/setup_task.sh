#!/bin/bash
echo "=== Setting up election_1860_swing_states_analysis task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing files
rm -f /home/ga/Documents/analyze_1860.py 2>/dev/null || true
rm -f /home/ga/Documents/swing_states_1860.html 2>/dev/null || true

# Record task start timestamp for mtime validation
date +%s > /tmp/task_start_ts
chmod 666 /tmp/task_start_ts

# Create the real historical 1860 election dataset
# Data: State, Lincoln, Douglas, Breckinridge, Bell
cat > /home/ga/Documents/election_1860.csv << 'EOF'
State,Lincoln,Douglas,Breckinridge,Bell
California,38733,37999,33969,9111
Oregon,5344,4131,5074,212
Virginia,1887,16198,74325,74481
Missouri,17028,58801,31362,58372
Illinois,172171,160215,2331,4914
New York,362646,312510,0,0
Ohio,231709,153012,11405,12194
Texas,0,0,47548,15438
Pennsylvania,268030,178871,37954,12776
Massachusetts,106533,34372,5939,22331
Kentucky,1364,25651,53143,66058
Indiana,139033,115509,12295,5306
Iowa,70409,55111,1048,1763
EOF
chown ga:ga /home/ga/Documents/election_1860.csv

# Close any open activity first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Launch the Terminal activity
echo "Launching Terminal activity..."
su - ga -c "$SUGAR_ENV sugar-launch org.laptop.Terminal" &
sleep 10

# Verify Terminal is running
if pgrep -f "Terminal\|terminal" > /dev/null 2>&1; then
    echo "Terminal activity is running"
else
    echo "WARNING: Terminal activity may not have started"
fi

# Take a verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/task_initial_state.png" 2>/dev/null || true

echo "=== Setup complete ==="
echo "Terminal is open. Dataset is at /home/ga/Documents/election_1860.csv."