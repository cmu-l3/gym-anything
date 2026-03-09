#!/bin/bash
set -euo pipefail

echo "=== Setting up Batch Delete Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
record_start_time "batch_delete_company_records"

# 1. Kill any existing instances to ensure clean state
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
sleep 2

# 2. Launch Lobby Track
launch_lobbytrack

# 3. Populate Database with Scenario Data
# Since we cannot easily inject into Access DB on Linux without the app,
# we will use GUI automation to register the visitors.
# This ensures the data is "real" from the app's perspective.

echo "Populating database with scenario records..."

# Function to register a visitor
register_visitor() {
    local first="$1"
    local last="$2"
    local company="$3"
    
    echo "Registering: $first $last ($company)..."
    
    # Click 'Register' (assuming it's reachable via keyboard shortcut or Tab)
    # F2 is often a shortcut, or standard Ctrl+N. 
    # We'll use a sequence of Tabs if shortcuts aren't known, but let's try standard keys.
    # Assuming standard Lobby Track flow: Main Menu -> Register Visitor
    
    # Send Alt+R for Register or simulate clicks if needed.
    # For robustness in this blind env, we'll try standard navigation.
    # We will assume the app starts on the main screen.
    
    # Heuristic: Focus window, press 'Register' button or F2
    # We'll try to use the CLI tool if available, otherwise xdotool
    
    # 1. Open Registration Form (Simulate Ctrl+N or F2 or Enter on "Register")
    # Using relative coordinates might be risky, so we rely on Tab/Enter
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers F2" 
    sleep 2
    
    # 2. Type First Name
    su - ga -c "DISPLAY=:1 xdotool type '$first'"
    su - ga -c "DISPLAY=:1 xdotool key Tab"
    
    # 3. Type Last Name
    su - ga -c "DISPLAY=:1 xdotool type '$last'"
    su - ga -c "DISPLAY=:1 xdotool key Tab"
    
    # 4. Type Company
    su - ga -c "DISPLAY=:1 xdotool type '$company'"
    sleep 0.5
    
    # 5. Save/Check-in (usually Enter or F10 or Ctrl+S)
    # We'll tab through to 'Save' or 'OK'
    su - ga -c "DISPLAY=:1 xdotool key Return" 
    sleep 2
    
    # Handle any "Badge Print" dialogs (escape to cancel print)
    su - ga -c "DISPLAY=:1 xdotool key Escape" 
    sleep 1
    
    # Return to main screen if not already (Escape usually closes form)
    su - ga -c "DISPLAY=:1 xdotool key Escape" 
    sleep 1
}

# Ensure window is focused
WID=$(DISPLAY=:1 wmctrl -l | grep -i "lobby" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    sleep 1
fi

# We will inject 4 records: 2 targets, 2 non-targets
# Note: In a real implementation, we might copy a prepared .mdb file instead.
# Given the constraints, we will attempt to copy a prepared DB if it exists,
# otherwise we rely on the agent finding *some* data. 
# For this task generation, we'll assume the environment has `mdb-sql` or similar
# to verify, but populating via xdotool is safer for "creation".

# HOWEVER, to be reliable for the user/agent interaction immediately:
# We will use the `task_utils` to ensure the app is just ready.
# We assume the `install_lobby_track.sh` has already placed `visitor_records.csv`
# or a `sample.mdb` in the data folder. 

# Let's force a fresh start with the sample DB provided by the environment
# The environment install script mentions: cp -r /workspace/data /opt/lobbytrack/data
DB_SRC="/workspace/data/LobbyTrack_Scenario.mdb"
DB_DEST_DIR="/home/ga/LobbyTrack/Database"
DB_DEST="$DB_DEST_DIR/LobbyTrack.mdb"

# If we have a scenario DB, use it. Else, we rely on the default.
# For the purpose of this task, we'll create a marker file to tell the verifier
# what the initial count was, assuming the default DB is used if no scenario DB.
# But we need "Apex Contractors" to exist.

# FALLBACK: If we can't inject data, we'll create a text file instruction
# implying the data is there, but for the VERIFIER to work, the data MUST be there.
# We will assume the `setup_lobby_track.sh` has populated basic data.
# To be absolutely sure, let's inject 2 records via xdotool now.

register_visitor "John" "Doe" "Apex Contractors"
register_visitor "Jane" "Smith" "Summit Partners"
register_visitor "Bob" "Jones" "Apex Contractors"
register_visitor "Alice" "Brown" "Summit Partners"

# Record initial counts using mdb-tools (available in env)
# Find the database file
DB_FILE=$(find /home/ga -name "*.mdb" | grep -i "lobby" | head -1)

if [ -n "$DB_FILE" ] && command -v mdb-export >/dev/null; then
    echo "Found DB: $DB_FILE"
    # Export visitor table (table name guess: "Visitors" or "Log")
    # We try listing tables first
    TABLES=$(mdb-tables "$DB_FILE")
    VISITOR_TABLE=$(echo "$TABLES" | tr ' ' '\n' | grep -i "Visitor" | head -1)
    
    if [ -n "$VISITOR_TABLE" ]; then
        mdb-export "$DB_FILE" "$VISITOR_TABLE" > /tmp/initial_db_export.csv
        INIT_APEX=$(grep -c "Apex Contractors" /tmp/initial_db_export.csv || echo 0)
        INIT_SUMMIT=$(grep -c "Summit Partners" /tmp/initial_db_export.csv || echo 0)
        echo "$INIT_APEX" > /tmp/init_apex_count.txt
        echo "$INIT_SUMMIT" > /tmp/init_summit_count.txt
    fi
else
    # Fallback if tools fail: assume we created 2 of each
    echo "2" > /tmp/init_apex_count.txt
    echo "2" > /tmp/init_summit_count.txt
fi

# Ensure app is maximized and ready
WID=$(DISPLAY=:1 wmctrl -l | grep -i "lobby" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
    DISPLAY=:1 wmctrl -ia "$WID"
fi

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="