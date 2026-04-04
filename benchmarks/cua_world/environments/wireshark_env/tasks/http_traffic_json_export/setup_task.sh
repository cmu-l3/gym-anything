#!/bin/bash
set -e

echo "=== Setting up HTTP Traffic JSON Export Task ==="

# Define paths
PCAP_FILE="/home/ga/Documents/captures/http.cap"
GROUND_TRUTH_FILE="/tmp/ground_truth.json"

# Validate input file
if [ ! -f "$PCAP_FILE" ]; then
    echo "ERROR: PCAP file not found at $PCAP_FILE"
    exit 1
fi

# Generate Ground Truth (Hidden from agent)
# We filter for http.request and export specific fields to JSON
echo "Generating ground truth..."
tshark -r "$PCAP_FILE" \
    -Y "http.request" \
    -T json \
    -e frame.number \
    -e frame.time_epoch \
    -e ip.src \
    -e http.host \
    -e http.request.method \
    -e http.request.uri \
    > "$GROUND_TRUTH_FILE" 2>/dev/null

# Verify ground truth was created
if [ ! -s "$GROUND_TRUTH_FILE" ]; then
    echo "ERROR: Failed to generate ground truth"
    exit 1
fi

# Calculate expected packet count
EXPECTED_COUNT=$(grep -c "\"_index\"" "$GROUND_TRUTH_FILE")
echo "Expected HTTP Requests: $EXPECTED_COUNT" > /tmp/expected_count.txt

# Remove any previous output file to ensure clean state
rm -f "/home/ga/Documents/captures/http_requests.json"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Open Wireshark with the capture file as a visual aid
# (The agent might use GUI or CLI, we enable both)
echo "Starting Wireshark..."
su - ga -c "DISPLAY=:1 wireshark $PCAP_FILE > /dev/null 2>&1 &"

# Wait for Wireshark window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Wireshark"; then
        break
    fi
    sleep 1
done

# Maximize Wireshark
DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="