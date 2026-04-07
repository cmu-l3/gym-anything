#!/bin/bash
echo "=== Setting up english_letter_frequency_analysis task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Clean up any pre-existing agent output files
rm -f /home/ga/Documents/letter_freq.py 2>/dev/null || true
rm -f /home/ga/Documents/frequencies.csv 2>/dev/null || true

# Verify the input file exists (it should be placed by the environment definition)
if [ ! -f /home/ga/Documents/alice_in_wonderland.txt ]; then
    echo "WARNING: Input file missing, attempting to provide fallback..."
    if [ -f /workspace/data/alice_in_wonderland_excerpt.txt ]; then
        cp /workspace/data/alice_in_wonderland_excerpt.txt /home/ga/Documents/alice_in_wonderland.txt
        chown ga:ga /home/ga/Documents/alice_in_wonderland.txt
    else
        echo "ERROR: Could not find fallback data!"
    fi
fi

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

# Close any open activities to start from a clean home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Launch the Sugar Terminal Activity
echo "Launching Terminal activity..."
su - ga -c "$SUGAR_ENV sugar-launch org.laptop.Terminal" &
sleep 5

# Ensure window is maximized
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take verification screenshot of initial state
su - ga -c "$SUGAR_ENV scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== setup complete ==="