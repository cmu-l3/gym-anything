#!/bin/bash
echo "=== Setting up chapter_library_terminal task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/chapter_library_terminal_start_ts
chmod 666 /tmp/chapter_library_terminal_start_ts

# Ensure Documents exists and contains the required text file
mkdir -p /home/ga/Documents
if [ ! -f "/home/ga/Documents/alice_in_wonderland.txt" ]; then
    echo "Downloading alice text..."
    wget -q -O /home/ga/Documents/alice_in_wonderland.txt "https://www.gutenberg.org/cache/epub/11/pg11.txt" || true
fi
chown -R ga:ga /home/ga/Documents

# Clean up any existing library directory to ensure a clean state
rm -rf /home/ga/Library 2>/dev/null || true

# Close any open activity first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Launch the Terminal activity
echo "Launching Terminal activity..."
su - ga -c "$SUGAR_ENV sugar-launch org.laptop.Terminal" &
sleep 12

# Take verification screenshot of initial state
su - ga -c "$SUGAR_ENV scrot /tmp/terminal_task_start.png" 2>/dev/null || true

echo "=== chapter_library_terminal task setup complete ==="
echo "Sugar Terminal is open. Agent must split alice_in_wonderland.txt and create library files."