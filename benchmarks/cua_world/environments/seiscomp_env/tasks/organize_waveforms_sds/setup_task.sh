#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up organize_waveforms_sds task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Define paths
SOURCE_DATA="/workspace/data/fdsn" # Using bundled data as source
RAW_DUMP_DIR="/home/ga/Downloads/raw_dump"
ARCHIVE_DEST="/home/ga/Documents/ShadowArchive"

# Clean previous state
rm -rf "$RAW_DUMP_DIR" "$ARCHIVE_DEST"
mkdir -p "$RAW_DUMP_DIR"

# Prepare "Messy" Raw Data
echo "--- Preparing unsorted data ---"
COUNT=1
for FILE in "$SOURCE_DATA"/GE.*.mseed; do
    if [ -f "$FILE" ]; then
        DEST_NAME=$(printf "trace_data_%02d.mseed" "$COUNT")
        cp "$FILE" "$RAW_DUMP_DIR/$DEST_NAME"
        echo "Copied $(basename "$FILE") -> $DEST_NAME"
        COUNT=$((COUNT + 1))
    fi
done

# Save the total number of source files to expected file count
EXPECTED_COUNT=$((COUNT - 1))
echo "$EXPECTED_COUNT" > /tmp/expected_file_count.txt

chown -R ga:ga "/home/ga/Downloads"
chown -R ga:ga "/home/ga/Documents"

# Ensure SeisComP env is ready (messaging system for SeisComP tools)
ensure_scmaster_running

# Open the terminal for the agent
if ! pgrep -f "gnome-terminal" > /dev/null; then
    export DISPLAY=:1
    su - ga -c "DISPLAY=:1 /usr/bin/gnome-terminal --working-directory='/home/ga' &"
    sleep 2
fi

# Ensure terminal is focused and maximized
focus_and_maximize "Terminal"

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_start.png 2>/dev/null || true

echo "=== Task setup complete ==="