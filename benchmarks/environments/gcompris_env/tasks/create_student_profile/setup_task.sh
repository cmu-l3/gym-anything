#!/bin/bash
set -e
echo "=== Setting up Create Student Profile task ==="

# Load utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up any previous runs
rm -f /tmp/task_result.json

# Launch GCompris
# We use the shared utility to ensure it's launched correctly as 'ga'
# and we wait for the window to appear.
launch_gcompris

# Maximize the window for better visibility
maximize_gcompris

# Record initial user count from DB to verify a NEW user is added
# Find the database file
DB_FILE=$(find /home/ga/.local/share/GCompris -name "GCompris-*.db" | head -n 1)

if [ -f "$DB_FILE" ]; then
    echo "Database found at: $DB_FILE"
    # Use python to query safely
    INITIAL_COUNT=$(python3 -c "import sqlite3; conn=sqlite3.connect('$DB_FILE'); c=conn.cursor(); c.execute('SELECT COUNT(*) FROM users'); print(c.fetchone()[0])" 2>/dev/null || echo "0")
else
    echo "Warning: Database not found yet (will be created on first run/save)"
    INITIAL_COUNT="0"
fi
echo "$INITIAL_COUNT" > /tmp/initial_user_count.txt
echo "Initial user count: $INITIAL_COUNT"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="