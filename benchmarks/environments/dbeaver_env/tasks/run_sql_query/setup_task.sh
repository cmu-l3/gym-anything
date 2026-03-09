#!/bin/bash
# Setup script for run_sql_query task
# Records initial state before agent action

echo "=== Setting up Run SQL Query Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure DBeaver is running
if [ "$(is_dbeaver_running)" = "false" ]; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 10
fi

# Focus DBeaver window
focus_dbeaver

# Record initial state - verify the database has AC/DC tracks
echo "Verifying database state..."
ACDC_TRACKS=$(chinook_query "SELECT COUNT(*) FROM tracks t JOIN albums a ON t.AlbumId = a.AlbumId JOIN artists ar ON a.ArtistId = ar.ArtistId WHERE ar.Name = 'AC/DC';")
echo "AC/DC tracks in database: $ACDC_TRACKS"
echo "$ACDC_TRACKS" > /tmp/expected_acdc_tracks

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task Setup Complete ==="
