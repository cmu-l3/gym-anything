#!/bin/bash
# Do NOT use set -e to prevent premature termination
echo "=== Setting up alice_word_analysis_pippy task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists with correct permissions
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Verify alice_in_wonderland.txt exists (fallback if install script failed)
if [ ! -f /home/ga/Documents/alice_in_wonderland.txt ]; then
    echo "WARNING: alice_in_wonderland.txt not found. Attempting to download..."
    wget -q -O /home/ga/Documents/alice_in_wonderland.txt "https://www.gutenberg.org/cache/epub/11/pg11.txt" || true
    chown ga:ga /home/ga/Documents/alice_in_wonderland.txt
fi

# Remove any pre-existing agent files
rm -f /home/ga/Documents/alice_analysis.py 2>/dev/null || true
rm -f /home/ga/Documents/alice_analysis.txt 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/alice_task_start_ts
chmod 666 /tmp/alice_task_start_ts

# Close any open activity first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Launch the Pippy Python IDE activity
echo "Launching Pippy activity..."
su - ga -c "$SUGAR_ENV sugar-launch org.laptop.Pippy" &
sleep 12

# Fallback: if Pippy didn't start, launch Terminal
if ! pgrep -f "Pippy\|pippy" > /dev/null 2>&1; then
    echo "Pippy didn't start, launching Terminal as fallback..."
    su - ga -c "$SUGAR_ENV sugar-launch org.laptop.Terminal" &
    sleep 5
fi

# Take a verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/alice_task_start.png" 2>/dev/null || true

echo "=== alice_word_analysis_pippy task setup complete ==="
echo "Agent must write Python script to analyze alice_in_wonderland.txt,"
echo "save to /home/ga/Documents/alice_analysis.py, and generate /home/ga/Documents/alice_analysis.txt"