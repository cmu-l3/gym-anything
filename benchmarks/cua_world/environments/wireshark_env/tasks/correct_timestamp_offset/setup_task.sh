#!/bin/bash
set -e

echo "=== Setting up correct_timestamp_offset task ==="

# Load shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure the original file exists and is clean
ORIG_FILE="/home/ga/Documents/captures/http.cap"
BACKUP_FILE="/tmp/http_backup.cap"

if [ ! -f "$ORIG_FILE" ]; then
    echo "ERROR: Original file $ORIG_FILE not found!"
    exit 1
fi

# Create a backup of the original file to ensure we have a clean reference
# independent of what the agent does to the file in Documents
cp "$ORIG_FILE" "$BACKUP_FILE"

# Record baseline metrics for the original file
# 1. Packet count
# 2. Timestamp of the first packet (epoch time)
echo "Recording baseline metrics..."
ORIG_PACKET_COUNT=$(tshark -r "$BACKUP_FILE" 2>/dev/null | wc -l)
ORIG_START_TIME=$(tshark -r "$BACKUP_FILE" -c 1 -T fields -e frame.time_epoch 2>/dev/null)

echo "$ORIG_PACKET_COUNT" > /tmp/baseline_packet_count.txt
echo "$ORIG_START_TIME" > /tmp/baseline_start_time.txt

echo "Baseline: $ORIG_PACKET_COUNT packets, start time $ORIG_START_TIME"

# Remove any previous output file to ensure a fresh start
rm -f "/home/ga/Documents/captures/http_corrected.pcapng" 2>/dev/null || true
rm -f "/home/ga/Documents/captures/http_corrected.pcap" 2>/dev/null || true

# Start Wireshark with the file loaded
echo "Starting Wireshark..."
su - ga -c "DISPLAY=:1 wireshark $ORIG_FILE > /dev/null 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Wireshark"; then
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="