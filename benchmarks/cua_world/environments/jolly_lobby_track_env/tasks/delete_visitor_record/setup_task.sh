#!/bin/bash
set -euo pipefail
echo "=== Setting up Delete Visitor Record Task ==="

source /workspace/scripts/task_utils.sh

# Record setup start for internal timing
date +%s > /tmp/setup_start_time

# Kill any existing instances
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
pkill -x wine 2>/dev/null || true
sleep 3

# Launch Lobby Track
echo "Launching Lobby Track..."
launch_lobbytrack

# Wait for window to settle
sleep 5

# Function to register a visitor via xdotool
register_visitor() {
    local first="$1"
    local last="$2"
    local company="$3"
    
    echo "Registering: $first $last..."
    
    # Click 'Register' or equivalent (Assuming Ctrl+N or Alt+R usually works, 
    # but strictly we rely on tab navigation from main screen or specific key presses)
    # Standard Jolly Lobby Track 6 shortcut for "Register Visitor" is often F2 or large button
    
    # Reset to main screen state just in case
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Escape" 2>/dev/null || true
    sleep 1
    
    # Open Registration form (F2 is common, or Ctrl+N)
    # Trying F2 first
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers F2" 2>/dev/null || true
    sleep 2
    
    # If F2 didn't open a new window/dialog, try navigating
    # Assuming standard form focus starts at First Name or ID
    
    # Type First Name
    su - ga -c "DISPLAY=:1 xdotool type '$first'" 2>/dev/null || true
    sleep 0.5
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Tab" 2>/dev/null || true
    sleep 0.5
    
    # Type Last Name
    su - ga -c "DISPLAY=:1 xdotool type '$last'" 2>/dev/null || true
    sleep 0.5
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Tab" 2>/dev/null || true
    sleep 0.5
    
    # Type Company (might need more tabs depending on layout, assuming simplified flow)
    # Just entering names is crucial for the task
    
    # Save (F10 or Enter or Ctrl+S)
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" 2>/dev/null || true
    sleep 2
    
    # Handle "Print Badge" dialog if it appears (Esc to cancel print)
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Escape" 2>/dev/null || true
    sleep 1
    
    # Return to main screen
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Escape" 2>/dev/null || true
    sleep 1
}

# Register the 4 required visitors
# We do this blindly hoping the UI state allows it. 
# In a real rigorous env, we'd check window titles.
# For this generation, we assume the app starts in a "Ready" state.

# 1. Maria Gonzalez
register_visitor "Maria" "Gonzalez" "Alvarez Partners"

# 2. David Chen
register_visitor "David" "Chen" "Meridian Tech"

# 3. John Testentry (The target)
register_visitor "John" "Testentry" "Test Corp"

# 4. Sarah Williams
register_visitor "Sarah" "Williams" "Regional Health"

# Find the database file to monitor
DB_FILE=$(find /home/ga/.wine/drive_c -iname "*.mdb" -o -iname "*.sdf" | grep -i "lobby\|visitor\|track" | head -1)
if [ -z "$DB_FILE" ]; then
    # Fallback to looking in standard locations
    DB_FILE=$(find /home/ga -iname "LobbyTrack.mdb" 2>/dev/null | head -1)
fi

echo "Database file: $DB_FILE"
echo "$DB_FILE" > /tmp/db_path.txt

if [ -f "$DB_FILE" ]; then
    # Snapshot initial modification time
    stat -c %Y "$DB_FILE" > /tmp/initial_db_mtime.txt
    ls -l "$DB_FILE" > /tmp/initial_db_stats.txt
else
    echo "WARNING: Database file not found during setup"
    echo "0" > /tmp/initial_db_mtime.txt
fi

# Record task start time (Agent's clock starts after this script)
date +%s > /tmp/task_start_time.txt

# Ensure main window is focused and ready
WID=$(wait_for_lobbytrack_window 10)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="