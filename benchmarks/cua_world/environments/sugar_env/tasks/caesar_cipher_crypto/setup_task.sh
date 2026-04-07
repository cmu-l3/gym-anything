#!/bin/bash
echo "=== Setting up caesar_cipher_crypto task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure clean slate for the target directory
rm -rf /home/ga/Documents/crypto 2>/dev/null || true
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

# Close any open activities to ensure we start at the Sugar home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Make sure Sugar session is running
if ! pgrep -f "jarabe.main" > /dev/null 2>&1; then
    echo "Sugar session not found, restarting..."
    systemctl restart gdm 2>/dev/null || true
    sleep 15
fi

# Take verification screenshot of initial state
su - ga -c "$SUGAR_ENV scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Agent must create a python program implementing Caesar cipher in /home/ga/Documents/crypto/"