#!/bin/bash
set -e
echo "=== Setting up Export Contractor Activity task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
record_start_time "export_contractor_activity"

# Clean up any previous runs
rm -f /home/ga/Documents/contractor_activity.csv 2>/dev/null || true

# Ensure Lobby Track is running and clean
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
sleep 2

# Launch Lobby Track
launch_lobbytrack

# Wait for window
WID=$(wait_for_lobbytrack_window 60)
if [ -z "$WID" ]; then
    echo "ERROR: Lobby Track window not found"
    exit 1
fi

# Maximize
DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Lobby" 2>/dev/null || true

# Inject Data via UI Automation (xdotool)
# We need to ensure specific records exist for the filter test.
# We will inject 3 records: 1 Contractor, 1 Interview, 1 Contractor.
echo "Injecting visitor data..."

# Function to type keys safely
type_text() {
    DISPLAY=:1 xdotool type --delay 50 "$1"
}

# Function to press key
press_key() {
    DISPLAY=:1 xdotool key --delay 100 "$1"
}

# Navigate to Registration (assuming F2 or Ctrl+N hotkeys work, or just relying on Tab cycle)
# We'll try a sequence to get to "Register Visitor"
press_key "Escape" 
sleep 0.5
press_key "Escape" # Clear dialogs
sleep 1

# Register Visitor 1: Contractor (Gary Spark)
echo "Registering Gary Spark (Contractor)..."
# Shortcut for Register Visitor often Alt+R or Ctrl+N in these apps
press_key "ctrl+n"
sleep 2
type_text "Gary"
press_key "Tab"
type_text "Spark"
press_key "Tab"
# Skip to Purpose (assuming tab order: First, Last, Company, ID, Purpose)
press_key "Tab" 
press_key "Tab"
type_text "Spark Electric" # Company
press_key "Tab"
# Purpose field
type_text "Contractor"
sleep 0.5
press_key "Return" # Save/Check-in
sleep 4
press_key "Escape" # Dismiss badge print or confirmation
sleep 1

# Register Visitor 2: Interview (Alice Candidate)
echo "Registering Alice Candidate (Interview)..."
press_key "ctrl+n"
sleep 2
type_text "Alice"
press_key "Tab"
type_text "Candidate"
press_key "Tab"
press_key "Tab"
press_key "Tab"
type_text "None"
press_key "Tab"
type_text "Interview"
sleep 0.5
press_key "Return"
sleep 4
press_key "Escape"
sleep 1

# Register Visitor 3: Contractor (Joe Plumber)
echo "Registering Joe Plumber (Contractor)..."
press_key "ctrl+n"
sleep 2
type_text "Joe"
press_key "Tab"
type_text "Plumber"
press_key "Tab"
press_key "Tab"
press_key "Tab"
type_text "FixIt Plumbers"
press_key "Tab"
type_text "Contractor"
sleep 0.5
press_key "Return"
sleep 4
press_key "Escape"
sleep 1

# Return to main screen/log
press_key "Escape"
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="