#!/bin/bash
echo "=== Setting up math_quiz_html task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing file to ensure agent creates it fresh
rm -f /home/ga/Documents/math_quiz.html 2>/dev/null || true

# Record task start timestamp for mtime validation
date +%s > /tmp/math_quiz_start_ts
chmod 666 /tmp/math_quiz_start_ts

# Close any open activity first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Verify Sugar session is running
if ! pgrep -f "jarabe.main" > /dev/null 2>&1; then
    echo "Sugar session not found, attempting to restart..."
    systemctl restart gdm 2>/dev/null || true
    sleep 15
fi

# Take a verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/math_quiz_start.png" 2>/dev/null || true

echo "=== math_quiz_html task setup complete ==="
echo "Sugar desktop is open. Agent must write /home/ga/Documents/math_quiz.html using Terminal."