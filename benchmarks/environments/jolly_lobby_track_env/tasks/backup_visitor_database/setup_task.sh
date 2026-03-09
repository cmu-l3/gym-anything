#!/bin/bash
set -e
echo "=== Setting up backup_visitor_database task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task started at: $(cat /tmp/task_start_time.txt)"

# Clean up any previous attempts
rm -rf /home/ga/Documents/LobbyTrackBackup 2>/dev/null || true

# Pre-locate the database for ground truth (hidden from agent)
# Look in common Wine locations for Lobby Track data
echo "Locating actual database for verification..."
DB_CANDIDATES=$(find /home/ga/.wine/drive_c -type f \( -iname "*.sdf" -o -iname "*.mdb" -o -iname "*.db" -o -iname "*.sqlite" \) -not -path "*/Windows/*" -not -path "*/Temp/*" 2>/dev/null)

# Filter for likely Lobby Track files
REAL_DB=""
for db in $DB_CANDIDATES; do
    if echo "$db" | grep -qi "Lobby\|Jolly\|Visitor"; then
        REAL_DB="$db"
        break
    fi
done

# Fallback if specific name not found
if [ -z "$REAL_DB" ] && [ -n "$DB_CANDIDATES" ]; then
    REAL_DB=$(echo "$DB_CANDIDATES" | head -n 1)
fi

if [ -n "$REAL_DB" ]; then
    echo "$REAL_DB" > /tmp/ground_truth_db_path.txt
    stat -c%s "$REAL_DB" > /tmp/ground_truth_db_size.txt
    echo "Ground truth DB identified: $REAL_DB ($(cat /tmp/ground_truth_db_size.txt) bytes)"
else
    echo "WARNING: Could not auto-detect database file. Verification will rely on heuristic checks."
    echo "" > /tmp/ground_truth_db_path.txt
    echo "0" > /tmp/ground_truth_db_size.txt
fi

# Ensure permissions are restricted for ground truth files
chmod 600 /tmp/ground_truth_db_path.txt /tmp/ground_truth_db_size.txt 2>/dev/null || true

# Ensure Lobby Track is running
ensure_lobbytrack_running

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="