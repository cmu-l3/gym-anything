#!/bin/bash
echo "=== Setting up pendulum_gravity_lab_report task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists with correct ownership
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing output file to ensure agent creates it fresh
rm -f /home/ga/Documents/pendulum_report.odt 2>/dev/null || true

# Record task start timestamp for anti-gaming (file modification verification)
date +%s > /tmp/pendulum_gravity_start_ts
chmod 666 /tmp/pendulum_gravity_start_ts

# Close any open activity first to return to the Sugar home view cleanly
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

# Take verification screenshot of initial state
su - ga -c "$SUGAR_ENV scrot /tmp/pendulum_task_start.png" 2>/dev/null || true

echo "=== pendulum_gravity_lab_report task setup complete ==="
echo "Sugar Write is open. Agent must calculate gravity values and create a lab report at /home/ga/Documents/pendulum_report.odt"