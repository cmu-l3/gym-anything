#!/bin/bash
set -e
echo "=== Setting up consolidate_genres task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Reset database to known state (fresh copy of chinook.odb)
setup_libreoffice_base_task /home/ga/chinook.odb

# Ensure Documents directory exists for the export
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing output file
rm -f /home/ga/Documents/heavy_music_tracks.csv

# Record initial file timestamp of the database
stat -c %Y /home/ga/chinook.odb > /tmp/initial_odb_mtime.txt

echo "=== Task setup complete ==="
echo "Task: Consolidate 'Rock' and 'Metal' into 'Heavy Music' and export tracks."