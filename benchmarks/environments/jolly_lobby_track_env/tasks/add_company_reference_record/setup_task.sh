#!/bin/bash
set -e
echo "=== Setting up Add Company Reference Record Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
record_start_time "add_company_reference_record"

# 1. Kill existing instances to ensure fresh start
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
sleep 2

# 2. Locate Database and Record Initial State
# We need to ensure 'Aramark' doesn't already exist to prevent false positives
DB_FILE=$(find /home/ga/.wine/drive_c -iname "LobbyTrack*.mdb" -o -iname "Sample*.mdb" 2>/dev/null | head -1)

if [ -n "$DB_FILE" ]; then
    echo "Database found at: $DB_FILE"
    
    # Check if Aramark already exists (simple string check on binary DB)
    if strings "$DB_FILE" | grep -iq "Aramark"; then
        echo "WARNING: 'Aramark' already found in database. Attempting to restore clean backup..."
        # In a real scenario, we might restore a backup here. 
        # For now, we note it for the verifier, but proceeding assuming the agent will 'add' it or edit it.
        # Ideally, we would cp a clean DB here.
        if [ -f "/workspace/data/LobbyTrack_clean.mdb" ]; then
            cp "/workspace/data/LobbyTrack_clean.mdb" "$DB_FILE"
            echo "Restored clean database."
        fi
    fi

    # Record initial file timestamp
    stat -c %Y "$DB_FILE" > /tmp/initial_db_mtime.txt
else
    echo "WARNING: No database file found during setup."
    echo "0" > /tmp/initial_db_mtime.txt
fi

# 3. Launch Lobby Track
launch_lobbytrack

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="