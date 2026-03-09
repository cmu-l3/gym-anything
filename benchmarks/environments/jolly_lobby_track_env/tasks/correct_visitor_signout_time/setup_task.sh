#!/bin/bash
set -e
echo "=== Setting up correct_visitor_signout_time task ==="

source /workspace/scripts/task_utils.sh

# 1. Record Start Time
record_start_time "correct_visitor_signout_time"

# 2. Clean up previous run artifacts
rm -f /home/ga/Documents/corrected_log.csv
rm -f /tmp/task_result.json

# 3. Launch Lobby Track
# We need to ensure the app is running and then inject the "Active Visitor" state
# via UI automation since we don't have a pre-baked database with this specific state.
launch_lobbytrack
sleep 5

# 4. Inject State: Register "Elena Fisher" as currently signed in
echo "Injecting task state: Signing in Elena Fisher..."

# Ensure we are on the main screen (Try Escaping any dialogs)
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Escape"
sleep 1

# Navigate to Registration / New Visitor (Assuming Ctrl+N or Alt+R standard shortcuts, 
# or tab navigation. Based on standard Lobby Track, we'll try a generic form entry sequence)
# If specific shortcuts aren't known, we rely on the fact that it usually opens to the Registration tab.

# Type First Name
su - ga -c "DISPLAY=:1 xdotool type 'Elena'"
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key Tab"
sleep 0.5

# Type Last Name
su - ga -c "DISPLAY=:1 xdotool type 'Fisher'"
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key Tab"
sleep 0.5

# Type Company (Assuming it's the next field or close to it)
# In many versions, Company is 3rd field.
su - ga -c "DISPLAY=:1 xdotool type 'Uncharted Supplies'"
sleep 0.5

# Trigger "Sign In" / "Save"
# Usually Enter triggers the default action (Sign In)
su - ga -c "DISPLAY=:1 xdotool key Return"
sleep 5

# Handle potential "Badge Print" dialog
su - ga -c "DISPLAY=:1 xdotool key Escape"
sleep 1

# 5. Capture Initial State Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete: Elena Fisher should be signed in ==="