#!/bin/bash
echo "=== Setting up sugar_system_inventory task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists with correct permissions
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing files to prevent gaming
rm -f /home/ga/Documents/inventory.sh 2>/dev/null || true
rm -f /home/ga/Documents/system_report.txt 2>/dev/null || true

# Record task start timestamp for mtime validation
date +%s > /tmp/sugar_system_inventory_start_ts
chmod 666 /tmp/sugar_system_inventory_start_ts

# Set known gsettings to ensure predictable user config
su - ga -c "$SUGAR_ENV gsettings set org.sugarlabs.user nick 'Learner'" 2>/dev/null || true
su - ga -c "$SUGAR_ENV gsettings set org.sugarlabs.user color '#FF2B34,#005FE4'" 2>/dev/null || true

# Close any open activities first to return to the Sugar home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Launch the Terminal activity directly
echo "Launching Terminal activity..."
su - ga -c "$SUGAR_ENV sugar-launch org.laptop.Terminal" &
sleep 10

# Verify Terminal is running
if pgrep -f "Terminal" > /dev/null 2>&1; then
    echo "Terminal activity is running"
else
    echo "WARNING: Terminal activity may not have started"
fi

# Take verification screenshot of initial state
su - ga -c "$SUGAR_ENV scrot /tmp/inventory_task_start.png" 2>/dev/null || true

echo "=== sugar_system_inventory task setup complete ==="