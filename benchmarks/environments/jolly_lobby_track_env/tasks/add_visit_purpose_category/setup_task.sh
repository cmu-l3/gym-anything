#!/bin/bash
set -e
echo "=== Setting up add_visit_purpose_category task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp check)
record_start_time "add_visit_purpose"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Clean up previous run artifacts
rm -f /home/ga/Documents/visit_purpose_confirmation.png
rm -f /tmp/db_initial_check.txt

# Find the database file to establish baseline
# Lobby Track usually uses an Access .mdb file, often named LobbyTrack.mdb or similar
echo "Locating database file..."
DB_FILE=$(find /home/ga/.wine/drive_c -iname "LobbyTrack.mdb" -o -iname "Lobby.mdb" -o -iname "*.mdb" 2>/dev/null | grep -v "Sample" | head -1)

if [ -z "$DB_FILE" ]; then
    # Fallback search
    DB_FILE=$(find /home/ga/.wine/drive_c -name "*.mdb" 2>/dev/null | head -1)
fi

echo "Database file candidate: $DB_FILE"

# Check if target string already exists (it shouldn't)
if [ -n "$DB_FILE" ] && [ -f "$DB_FILE" ]; then
    # Use strings to check binary file for text content
    if strings "$DB_FILE" | grep -qi "Facility Maintenance"; then
        echo "WARNING: 'Facility Maintenance' already found in DB. Attempting to backup/reset."
        # In a real scenario we might reset the DB here, but for now we just log it
        echo "exists" > /tmp/db_initial_check.txt
    else
        echo "clean" > /tmp/db_initial_check.txt
    fi
else
    echo "not_found" > /tmp/db_initial_check.txt
fi

# Ensure Lobby Track is running and focused
ensure_lobbytrack_running

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="