#!/bin/bash
echo "=== Setting up monte_carlo_pi_estimation task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure clean state (remove pre-existing projects so agent must create them)
rm -rf /home/ga/Documents/math_projects 2>/dev/null || true

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/pi_task_start_ts
chmod 666 /tmp/pi_task_start_ts

# Close any open activity first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Launch Terminal to make it easier to write and run code
echo "Launching Terminal activity..."
su - ga -c "$SUGAR_ENV sugar-launch org.laptop.Terminal" &
sleep 10

# Verify Terminal is running
if pgrep -f "Terminal" > /dev/null 2>&1; then
    echo "Terminal activity is running"
else
    echo "WARNING: Terminal activity may not have started"
fi

# Take verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/pi_task_start.png" 2>/dev/null || true

echo "=== setup complete ==="