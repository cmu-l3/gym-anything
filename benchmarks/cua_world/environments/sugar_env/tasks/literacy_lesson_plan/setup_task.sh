#!/bin/bash
# Do NOT use set -e
echo "=== Setting up literacy_lesson_plan task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing file
rm -f /home/ga/Documents/literacy_plan.odt 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/literacy_lesson_plan_start_ts
chmod 666 /tmp/literacy_lesson_plan_start_ts

# Close any open activity first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Launch the Write (AbiWord) activity
echo "Launching Write activity..."
su - ga -c "$SUGAR_ENV sugar-launch org.laptop.AbiWordActivity" &
sleep 12

# Verify Write is running
if pgrep -f "AbiWordActivity\|abiword" > /dev/null 2>&1; then
    echo "Write activity is running"
else
    echo "WARNING: Write activity may not have started"
fi

# Take verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/literacy_task_start.png" 2>/dev/null || true

echo "=== literacy_lesson_plan task setup complete ==="
echo "Sugar Write is open. Agent must create lesson plan with headings, table, and save as literacy_plan.odt"
