#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Extract HTTP Objects task ==="

# 1. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Prepare directories
PCAP_FILE="/home/ga/Documents/captures/http.cap"
OUTPUT_DIR="/home/ga/Documents/extracted_objects"
REPORT_FILE="/home/ga/Documents/http_extraction_report.txt"
GT_DIR="/var/lib/wireshark_ground_truth"

# Ensure PCAP exists
if [ ! -f "$PCAP_FILE" ]; then
    echo "ERROR: $PCAP_FILE not found!"
    exit 1
fi

# Clean up previous run artifacts
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"
rm -f "$REPORT_FILE"

# 3. Generate Ground Truth (Hidden from agent)
echo "Generating ground truth..."
rm -rf "$GT_DIR"
mkdir -p "$GT_DIR/objects"

# Use tshark to extract objects to the hidden ground truth dir
# Note: tshark --export-objects saves files with their HTTP filenames
tshark -r "$PCAP_FILE" --export-objects "http,$GT_DIR/objects" > /dev/null 2>&1 || true

# Generate a JSON index of the ground truth for the verifier
# Structure: { "filename": "md5_hash", ... }
python3 -c "
import os
import json
import hashlib

gt_path = '$GT_DIR/objects'
result = {}
if os.path.exists(gt_path):
    for fname in os.listdir(gt_path):
        full_path = os.path.join(gt_path, fname)
        if os.path.isfile(full_path):
            with open(full_path, 'rb') as f:
                file_hash = hashlib.md5(f.read()).hexdigest()
            result[fname] = file_hash

with open('$GT_DIR/ground_truth.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Also extract hostnames for report verification
tshark -r "$PCAP_FILE" -Y "http.response" -T fields -e http.host 2>/dev/null | sort -u > "$GT_DIR/expected_hosts.txt"

chmod -R 700 "$GT_DIR"

# 4. Launch Wireshark
echo "Launching Wireshark..."
pkill -f wireshark 2>/dev/null || true
sleep 1

su - ga -c "DISPLAY=:1 wireshark '$PCAP_FILE' > /dev/null 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Wireshark"; then
        echo "Wireshark window detected"
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 5. Capture Initial State
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="