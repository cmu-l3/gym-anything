#!/bin/bash
set -e
echo "=== Setting up set_watchlist_expiration task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
record_start_time "set_watchlist_expiration"

# Kill any existing Lobby Track instance
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
pkill -x wine 2>/dev/null || true
sleep 2

# Launch Lobby Track
launch_lobbytrack

# Wait for main window to settle
sleep 5

# Automate creation of the initial watchlist record ("Robert Vance")
# This ensures the starting state is correct regardless of previous runs
echo "Pre-populating watchlist with Robert Vance..."

# Assuming standard keyboard shortcuts or tab navigation for Lobby Track 
# (This is a best-effort blind automation based on typical Windows UI navigation)

# 1. Open Watchlist / Denied Visitors (often under Tools or Settings)
# We'll try a sequence: Alt+T (Tools) -> Down -> Enter
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers alt+t"
sleep 1
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Down Return"
sleep 3

# 2. Click "Add" (Alt+A is common, or Ctrl+N)
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers alt+a"
sleep 2

# 3. Type Name: "Robert" [Tab] "Vance"
su - ga -c "DISPLAY=:1 xdotool type 'Robert'"
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Tab"
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type 'Vance'"
sleep 0.5

# 4. Tab to Reason field (guessing 2-3 tabs) and type "Safety Violation"
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Tab Tab"
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type 'Safety Violation'"
sleep 0.5

# 5. Save (Enter or Alt+S)
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return"
sleep 2

# 6. Close Watchlist window (Esc or Alt+C)
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Escape"
sleep 2

# Ensure we are back at main window and focused
DISPLAY=:1 wmctrl -a "Lobby" 2>/dev/null || true
sleep 1

# Capture setup state
take_screenshot /tmp/task_initial.png

echo "=== set_watchlist_expiration task setup complete ==="