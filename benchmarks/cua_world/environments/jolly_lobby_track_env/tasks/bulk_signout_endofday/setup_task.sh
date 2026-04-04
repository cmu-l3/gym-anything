#!/bin/bash
set -e
echo "=== Setting up Bulk Sign-out Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure Lobby Track is running and clean
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
sleep 2

# Launch Lobby Track
echo "Launching Lobby Track..."
launch_lobbytrack

# Wait for window to be ready
WID=$(wait_for_lobbytrack_window 60)
if [ -z "$WID" ]; then
    echo "ERROR: Lobby Track failed to start"
    exit 1
fi

# Focus and maximize
DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
sleep 2

# Function to register a visitor via UI automation
# Note: This relies on the default tab order of Lobby Track Free
register_visitor() {
    local fname="$1"
    local lname="$2"
    local company="$3"
    
    echo "Registering visitor: $fname $lname ($company)..."
    
    # Click "Register" or "Sign In" (Assuming shortcut or button position)
    # Using keyboard navigation to be safer than coordinates
    
    # Alt+R usually triggers Register/Sign In in this version, or F2
    # We'll try standard keys. If specific hotkeys fail, we might need to rely on the agent finding them blank,
    # but the task requires them to be signed in. 
    # Let's try to simulate a standard "New" flow.
    
    # 1. Open Registration form (Ctrl+N often works, or clicking the button)
    # Since specific shortcuts vary, we'll try a sequence that resets to Home then clicks Register
    
    # Focus window
    DISPLAY=:1 wmctrl -a "Lobby"
    sleep 0.5
    
    # Press F2 (common for "New/Register" in Jolly apps) or Ctrl+I (Check In)
    DISPLAY=:1 xdotool key F2
    sleep 2
    
    # Type First Name
    DISPLAY=:1 xdotool type "$fname"
    DISPLAY=:1 xdotool key Tab
    sleep 0.5
    
    # Type Last Name
    DISPLAY=:1 xdotool type "$lname"
    DISPLAY=:1 xdotool key Tab
    sleep 0.5
    
    # Skip to Company (assume a few tabs down, usually Name -> Company -> Host)
    # Adjust tabs based on typical form layout
    DISPLAY=:1 xdotool type "$company"
    sleep 0.5
    
    # Press Enter to Save/Check In
    DISPLAY=:1 xdotool key Return
    sleep 3
    
    # If a badge print dialog appears, dismiss it (Esc or Enter)
    DISPLAY=:1 xdotool key Escape
    sleep 1
    
    # Return to main screen (Esc usually closes dialogs)
    DISPLAY=:1 xdotool key Escape
    sleep 1
}

# Register the 3 visitors
# We wrap this in a block to ensure we attempt it, but don't fail hard if UI is laggy
# The agent will have to deal with whatever state we manage to set up, 
# but we aim for 3 active visitors.

echo "Populating visitor list..."

# Visitor 1
register_visitor "Margaret" "Chen" "Apex Consulting"
sleep 1

# Visitor 2
register_visitor "James" "Rodriguez" "FedEx"
sleep 1

# Visitor 3
register_visitor "Priya" "Nair" "NairTech"
sleep 1

# Ensure we are on the "View" or "Log" screen to show the list
# F3 often toggles View/Log
DISPLAY=:1 xdotool key F3
sleep 1

# Take initial screenshot for verification reference
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Setup Complete ==="