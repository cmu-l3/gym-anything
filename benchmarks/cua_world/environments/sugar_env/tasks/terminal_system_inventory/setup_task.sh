#!/bin/bash
# Do NOT use set -e
echo "=== Setting up terminal_system_inventory task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove pre-existing file
rm -f /home/ga/Documents/system_inventory.txt 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/terminal_system_inventory_start_ts
chmod 666 /tmp/terminal_system_inventory_start_ts

# Close any open activity first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Capture ground truth
uname -r > /tmp/gt_kernel.txt
ls -1 /usr/share/sugar/activities/ > /tmp/gt_activities.txt
su - ga -c "$SUGAR_ENV gsettings get org.sugarlabs.user nick" > /tmp/gt_nick.txt 2>/dev/null || echo "'Learner'" > /tmp/gt_nick.txt
su - ga -c "$SUGAR_ENV gsettings get org.sugarlabs.user color" > /tmp/gt_color.txt 2>/dev/null || echo "unknown" > /tmp/gt_color.txt

chmod 666 /tmp/gt_*.txt

# Launch Terminal
echo "Launching Terminal activity..."
su - ga -c "$SUGAR_ENV sugar-launch org.laptop.Terminal" &
sleep 10

# Verify Terminal is running
if pgrep -f -i "Terminal" > /dev/null 2>&1; then
    echo "Terminal activity is running"
else
    echo "WARNING: Terminal activity may not have started"
fi

# Take verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/terminal_task_start.png" 2>/dev/null || true

echo "=== terminal_system_inventory task setup complete ==="