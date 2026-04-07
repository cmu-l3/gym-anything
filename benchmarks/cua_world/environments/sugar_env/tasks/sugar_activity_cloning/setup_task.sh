#!/bin/bash
echo "=== Setting up sugar_activity_cloning task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_ts
chmod 666 /tmp/task_start_ts

# Ensure a clean state: remove any previous task artifacts
rm -rf /home/ga/Activities/MathTools.activity
rm -f /home/ga/Documents/activity_clone_report.txt

# Ensure directories exist with correct permissions
mkdir -p /home/ga/Activities
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Activities
chown -R ga:ga /home/ga/Documents

# Extract the actual original bundle ID from the system Calculate activity
# This ensures verification is accurate even if the system package changes slightly
CALC_INFO="/usr/share/sugar/activities/Calculate.activity/activity/activity.info"
if [ -f "$CALC_INFO" ]; then
    ORIGINAL_ID=$(grep "^bundle_id" "$CALC_INFO" | cut -d'=' -f2 | tr -d ' ' || echo "org.laptop.Calculate")
else
    ORIGINAL_ID="org.laptop.Calculate"
fi
echo "$ORIGINAL_ID" > /tmp/original_bundle_id
chmod 666 /tmp/original_bundle_id

# Ensure Sugar home view is showing
if ! pgrep -f "jarabe.main" > /dev/null 2>&1; then
    echo "Sugar session not found, attempting to restart..."
    systemctl restart gdm 2>/dev/null || true
    sleep 15
fi

# Close any open activities to return to the home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 2

# Take initial verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== sugar_activity_cloning task setup complete ==="