#!/bin/bash
# Do NOT use set -e
echo "=== Setting up student_profile_config task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Record task start timestamp
date +%s > /tmp/student_profile_config_start_ts
chmod 666 /tmp/student_profile_config_start_ts

# Reset profile to known state: nick="Learner", color=default red/blue
su - ga -c "$SUGAR_ENV gsettings set org.sugarlabs.user nick 'Learner'" 2>/dev/null || true
su - ga -c "$SUGAR_ENV gsettings set org.sugarlabs.user color '#FF2B34,#005FE4'" 2>/dev/null || true

# Close any open activity first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Ensure Sugar home view is showing (restart GDM session if needed)
if ! pgrep -f "jarabe.main" > /dev/null 2>&1; then
    echo "Sugar session not found, attempting to restart..."
    systemctl restart gdm 2>/dev/null || true
    sleep 15
fi

# Take verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/profile_task_start.png" 2>/dev/null || true

echo "=== student_profile_config task setup complete ==="
echo "Sugar home view ready. Profile reset: nick=Learner, color=#FF2B34,#005FE4"
echo "Agent must: set nick=AlexC, change color to warm/orange preset, create Write document 'Student Setup Log'"
