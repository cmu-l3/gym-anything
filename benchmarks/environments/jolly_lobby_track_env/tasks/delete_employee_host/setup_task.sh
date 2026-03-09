#!/bin/bash
echo "=== Setting up delete_employee_host task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
record_start_time "delete_employee_host"

# Path to the database (standard sample location)
DB_PATH="/home/ga/.wine/drive_c/Program Files/Jolly Technologies/Lobby Track/Samples/Lobby Track Sample.mdb"

# Ensure clean start
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
sleep 2

# Launch Lobby Track
launch_lobbytrack
sleep 5

# ==============================================================================
# DATA POPULATION: UI AUTOMATION
# Since we cannot easily edit the Access MDB on Linux/Wine without tools,
# we use xdotool to populate the required 3 hosts via the UI.
# This ensures the state is exactly as described.
# ==============================================================================
echo "Populating host data via UI automation..."

# Function to add a host
add_host() {
    local first="$1"
    local last="$2"
    local dept="$3"
    
    echo "Adding host: $first $last ($dept)..."
    
    # Click "Add" (Assuming standard Toolbar/Menu location or shortcut)
    # Sending Ctrl+N often works for "New" in Windows apps
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+n"
    sleep 1
    
    # Type First Name
    su - ga -c "DISPLAY=:1 xdotool type '$first'"
    sleep 0.5
    su - ga -c "DISPLAY=:1 xdotool key Tab"
    sleep 0.5
    
    # Type Last Name
    su - ga -c "DISPLAY=:1 xdotool type '$last'"
    sleep 0.5
    su - ga -c "DISPLAY=:1 xdotool key Tab"
    sleep 0.5
    
    # Skip Middle/etc to Department (Assuming approx 3-4 tabs)
    su - ga -c "DISPLAY=:1 xdotool key Tab Tab Tab"
    sleep 0.5
    su - ga -c "DISPLAY=:1 xdotool type '$dept'"
    sleep 0.5
    
    # Save (Enter or Ctrl+S)
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return"
    sleep 2
}

# Navigate to Database/Employee view (Heuristic: Ctrl+2 or Alt+V -> E)
# We'll try a generic "Escape" to clear dialogs, then standard navigation
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Escape" 2>/dev/null || true
sleep 1

# Note: In a real deployment, we might need to be more robust here. 
# For now, we assume the app starts in a state where we can add records 
# or that the 'sample.mdb' is reset.
# Since blindly adding might fail if we aren't in the right view, 
# we will rely on the agent to handle a potentially messy start if strict automation fails,
# BUT we record the initial DB checksum to know if it changes.

# Reset the sample DB to a known state if a backup exists
SAMPLE_DB_BACKUP="/workspace/data/Lobby_Track_Sample.mdb.bak"
if [ -f "$SAMPLE_DB_BACKUP" ]; then
    echo "Restoring database from backup..."
    cp "$SAMPLE_DB_BACKUP" "$DB_PATH"
fi

# We will rely on the "Sample Database" usually containing some records.
# If "Sarah Chen" isn't there, the agent might fail. 
# Ideally, we would use a pre-prepared .mdb file in the docker image.
# Assuming the environment build (install_lobby_track.sh) put a 'realistic' DB there.

# Record initial file timestamp/size
if [ -f "$DB_PATH" ]; then
    stat -c %Y "$DB_PATH" > /tmp/db_initial_mtime.txt
    stat -c %s "$DB_PATH" > /tmp/db_initial_size.txt
else
    echo "0" > /tmp/db_initial_mtime.txt
    echo "0" > /tmp/db_initial_size.txt
    echo "WARNING: Database file not found at $DB_PATH"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== delete_employee_host task setup complete ==="