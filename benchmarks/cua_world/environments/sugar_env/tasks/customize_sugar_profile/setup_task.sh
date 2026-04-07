#!/bin/bash
echo "=== Setting up customize_sugar_profile task ==="

# Sugar runs as the GDM session on :1.
# Commands need the user's DBUS session bus for gsettings.
SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Close any open activity to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Press F3 to ensure we're on the home view (Sugar shortcut for home)
su - ga -c "$SUGAR_ENV xdotool key F3" 2>/dev/null || true
sleep 2

# Ensure the nickname is set to 'Learner' (the starting state)
su - ga -c "$SUGAR_ENV gsettings set org.sugarlabs.user nick 'Learner'" 2>/dev/null || true

# Take a verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/task_start_state.png" 2>/dev/null || true

echo "=== customize_sugar_profile task setup complete ==="
echo "Sugar home view should be visible with XO icon in center"
echo "Current nickname is 'Learner' - agent should change it to 'Explorer'"
