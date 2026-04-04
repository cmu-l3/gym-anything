#!/bin/bash
set -e
echo "=== Setting up restore_visitor_database task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# 1. LOCATE ACTIVE DATABASE
# ==============================================================================
echo "Locating Lobby Track database..."
# Typical location for Jolly Lobby Track (Free/Standard)
# Usually in ProgramData or Common AppData, or sometimes adjacent to EXE
DB_PATH=""
POSSIBLE_PATHS=(
    "/home/ga/.wine/drive_c/ProgramData/Jolly Technologies/Lobby Track/Database/LobbyTrack.mdb"
    "/home/ga/.wine/drive_c/users/Public/Application Data/Jolly Technologies/Lobby Track/Database/LobbyTrack.mdb"
    "/home/ga/.wine/drive_c/Program Files/Jolly Technologies/Lobby Track/Database/LobbyTrack.mdb"
    "/home/ga/.wine/drive_c/LobbyTrack/Database/LobbyTrack.mdb"
)

for path in "${POSSIBLE_PATHS[@]}"; do
    if [ -f "$path" ]; then
        DB_PATH="$path"
        break
    fi
done

# If not found, try a broader search
if [ -z "$DB_PATH" ]; then
    DB_PATH=$(find /home/ga/.wine/drive_c -name "LobbyTrack.mdb" 2>/dev/null | head -1)
fi

if [ -z "$DB_PATH" ]; then
    echo "ERROR: Could not locate LobbyTrack.mdb database file."
    # Create a dummy one to allow task to proceed (simulation fallback)
    mkdir -p "/home/ga/.wine/drive_c/ProgramData/Jolly Technologies/Lobby Track/Database"
    DB_PATH="/home/ga/.wine/drive_c/ProgramData/Jolly Technologies/Lobby Track/Database/LobbyTrack.mdb"
    touch "$DB_PATH"
    # Fill with some dummy binary data to look like an MDB
    dd if=/dev/urandom of="$DB_PATH" bs=1024 count=500 2>/dev/null
fi

echo "Active Database found at: $DB_PATH"
echo "$DB_PATH" > /tmp/active_db_path.txt

# ==============================================================================
# 2. PREPARE BACKUP (THE "GOOD" STATE)
# ==============================================================================
BACKUP_DIR="/home/ga/.wine/drive_c/LobbyTrackBackup"
mkdir -p "$BACKUP_DIR"

# We want the backup to be "populated".
# If the current DB is small (empty), we might need to inject a populated one.
# For this environment, we assume the installed state has some sample data or we verify size.
# To ensure the backup is distinctly different from the empty state, we will append data if it's too small.
CURRENT_SIZE=$(stat -c%s "$DB_PATH" 2>/dev/null || echo 0)
if [ "$CURRENT_SIZE" -lt 100000 ]; then
    echo "Current DB seems small/empty. creating a larger 'backup' file..."
    # Simulate a larger MDB file
    dd if=/dev/urandom of="$BACKUP_DIR/LobbyTrackDB_backup.mdb" bs=1024 count=2048 2>/dev/null
else
    # Copy current populated DB as backup
    cp "$DB_PATH" "$BACKUP_DIR/LobbyTrackDB_backup.mdb"
fi

# Ensure backup has correct permissions
chmod 666 "$BACKUP_DIR/LobbyTrackDB_backup.mdb"
BACKUP_SIZE=$(stat -c%s "$BACKUP_DIR/LobbyTrackDB_backup.mdb")
echo "$BACKUP_SIZE" > /tmp/backup_db_size.txt
echo "Backup created at $BACKUP_DIR/LobbyTrackDB_backup.mdb ($BACKUP_SIZE bytes)"

# ==============================================================================
# 3. CREATE "DISASTER" STATE (EMPTY/NEW DATABASE)
# ==============================================================================
echo "Creating empty database state..."

# Kill app first
pkill -f "LobbyTrack" 2>/dev/null || true
pkill -f "Lobby" 2>/dev/null || true
sleep 2

# To simulate an empty DB, we can simply delete the active one.
# Lobby Track (like most apps) should regenerate a fresh, empty DB on startup.
# OR we replace it with a small empty file if we have a template.
# Strategy: Delete and let app regenerate.
rm -f "$DB_PATH"

# Launch Lobby Track to regenerate empty DB
echo "Launching Lobby Track to generate fresh empty DB..."
launch_lobbytrack

# Wait for regeneration
sleep 10

# Verify it was recreated
if [ ! -f "$DB_PATH" ]; then
    echo "WARNING: App did not recreate DB at expected path. Creating dummy empty DB."
    # Create small empty file
    dd if=/dev/zero of="$DB_PATH" bs=1024 count=100 2>/dev/null
fi

# Record the "Empty" size
EMPTY_SIZE=$(stat -c%s "$DB_PATH" 2>/dev/null || echo 0)
echo "$EMPTY_SIZE" > /tmp/empty_db_size.txt
echo "Active DB reset to empty state ($EMPTY_SIZE bytes)"

# ==============================================================================
# 4. CREATE INSTRUCTIONS
# ==============================================================================
cat > "$BACKUP_DIR/README.txt" << EOF
DISASTER RECOVERY INSTRUCTIONS
==============================

Problem: The active visitor database has been corrupted/lost.
Task: Restore the database using the backup file in this directory.

Backup File: C:\LobbyTrackBackup\LobbyTrackDB_backup.mdb

Steps:
1. Open Lobby Track (if not open).
2. Go to File > Restore Database (or Tools > Database > Restore).
   OR manually replace the active .mdb file with this backup.
3. Verify visitor records are visible.
4. Create a file named 'restore_confirmation.txt' in this folder 
   confirming the restore was successful.
EOF

# Open the backup folder in Explorer to give the agent a hint
su - ga -c "DISPLAY=:1 wine explorer /select,C:\\LobbyTrackBackup\\README.txt &"

# Ensure Lobby Track is maximized
WID=$(wait_for_lobbytrack_window 10)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="