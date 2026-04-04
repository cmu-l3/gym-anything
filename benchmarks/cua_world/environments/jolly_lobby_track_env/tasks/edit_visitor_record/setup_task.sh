#!/bin/bash
set -e
echo "=== Setting up edit_visitor_record task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp check)
record_start_time "edit_visitor_record"

# Ensure Documents directory exists for agent output
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# 1. Launch Lobby Track
echo "Launching Lobby Track..."
ensure_lobbytrack_running
sleep 5

# Focus the window
WID=$(wait_for_lobbytrack_window 10)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID"
    sleep 1
fi

# 2. Automate creating the "incorrect" record
echo "Creating initial visitor record (Maria Vasquez)..."

# Navigate to Sign In (Assuming standard hotkeys or Tab navigation)
# We'll use a sequence of Tab/Enter/Typing that works for the default UI
# Note: This sequence is a best-effort simulation of a user creating a record

# Reset UI state (Escape to close any open dialogs)
su - ga -c "DISPLAY=:1 xdotool key Escape Escape"
sleep 1

# Simulate Ctrl+I or similar to start sign in, or just Tab to the button
# We'll assume the 'Sign In' button is reachable via Tab
# For robustness in this blind setup, we'll try a common shortcut or just Tab cycling
# In Lobby Track, F2 often starts New Visitor or clicking the big button
su - ga -c "DISPLAY=:1 xdotool key F2"
sleep 2

# Type details
# Fields: First Name -> Tab -> Last Name -> Tab -> Company -> Tab -> ...
# We enter the INCORRECT details here for the agent to fix
echo "Typing visitor details..."
su - ga -c "DISPLAY=:1 xdotool type 'Maria'"
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key Tab"
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type 'Vasquez'"
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key Tab"
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type 'Prestige Worldwide Inc'" # Incorrect Company
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key Tab" # Email or other field, skipping for brevity if possible, or typing dummy
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type 'maria@example.com'"
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key Tab"
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type '555-0199'" # Incorrect Phone
sleep 0.5

# Save/Check In (Enter usually triggers the default action)
su - ga -c "DISPLAY=:1 xdotool key Return"
sleep 5

# Return to main screen (Escape or Close)
su - ga -c "DISPLAY=:1 xdotool key Escape"
sleep 2

# 3. Verify setup with screenshot
take_screenshot /tmp/setup_verification.png
echo "Setup screenshot captured to /tmp/setup_verification.png"

# 4. Final Window Management
# Ensure window is maximized and focused for the agent
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID"
fi

echo "=== Task setup complete ==="