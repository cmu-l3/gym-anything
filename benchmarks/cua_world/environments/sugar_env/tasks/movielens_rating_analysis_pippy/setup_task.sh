#!/bin/bash
echo "=== Setting up MovieLens Rating Analysis task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Download MovieLens 100k dataset if it doesn't exist
if [ ! -d "/home/ga/Documents/ml-100k" ]; then
    echo "Downloading MovieLens 100k dataset..."
    wget -q -O /tmp/ml-100k.zip "https://files.grouplens.org/datasets/movielens/ml-100k.zip"
    unzip -q /tmp/ml-100k.zip -d /home/ga/Documents/
    chown -R ga:ga /home/ga/Documents/ml-100k
    rm -f /tmp/ml-100k.zip
fi

# Remove any previous outputs to ensure a clean state
rm -f /home/ga/Documents/rating_analyzer.py
rm -f /home/ga/Documents/rating_summary.txt
rm -f /home/ga/Documents/rating_summary.html

# Record task start time
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

# Return to Sugar home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Take initial screenshot for evidence
su - ga -c "$SUGAR_ENV scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== Setup complete ==="