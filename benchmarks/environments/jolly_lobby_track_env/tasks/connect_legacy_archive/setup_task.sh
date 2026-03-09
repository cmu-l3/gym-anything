#!/bin/bash
set -e

echo "=== Setting up connect_legacy_archive task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# PREPARE REALISTIC DATA
# We need a valid database file. We will clone the currently installed sample DB
# to ensure the schema is 100% compatible with the installed version.
# ==============================================================================

echo "Locating valid database file..."
# Find any existing Lobby Track database in the Wine prefix or installation folder
SOURCE_DB=$(find /home/ga/.wine/drive_c -name "*.mdb" -o -name "*.sdf" 2>/dev/null | grep -i "lobby" | head -n 1)

if [ -z "$SOURCE_DB" ]; then
    echo "WARNING: No sample database found. Creating a placeholder (might fail connection test)."
    # Create a dummy file just in case, though this is not ideal
    touch "/home/ga/Documents/visitor_archive_2024.mdb"
    DB_EXT=".mdb"
else
    echo "Found source database: $SOURCE_DB"
    DB_EXT=".${SOURCE_DB##*.}"
    echo "Database extension: $DB_EXT"
    
    # Copy to Documents as the "Archive"
    TARGET_PATH="/home/ga/Documents/visitor_archive_2024${DB_EXT}"
    cp "$SOURCE_DB" "$TARGET_PATH"
    echo "Created archive database at: $TARGET_PATH"
fi

# Ensure correct permissions
chown ga:ga /home/ga/Documents/visitor_archive_2024*
chmod 666 /home/ga/Documents/visitor_archive_2024*

# Save the expected extension for the export script
echo "$DB_EXT" > /tmp/expected_db_ext.txt

# ==============================================================================
# APP LAUNCH
# ==============================================================================

# Ensure Lobby Track is running
ensure_lobbytrack_running

# Wait for window and maximize
WID=$(wait_for_lobbytrack_window 30)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="