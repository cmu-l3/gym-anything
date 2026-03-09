#!/bin/bash
set -e
echo "=== Setting up HTTP Session Timeline Reconstruction task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

PCAP_FILE="/home/ga/Documents/captures/http.cap"

if [ ! -s "$PCAP_FILE" ]; then
    echo "ERROR: PCAP file not found at $PCAP_FILE"
    # Try to redownload if missing (using script in env)
    wget -q -O "$PCAP_FILE" "https://wiki.wireshark.org/uploads/27707187aeb30df68e70c8fb9d614981/http.cap" || true
fi

# Ensure output directory exists and is clean
mkdir -p /home/ga/Documents/captures
rm -f /home/ga/Documents/captures/http_session_timeline.csv

# --- GENERATE GROUND TRUTH (Hidden) ---
GT_DIR="/var/lib/task/ground_truth"
mkdir -p "$GT_DIR"

# Generate the expected data rows using tshark
# We do NOT include the header in the tshark output here, we'll verify header separately
# or Prepend it for a full comparison file.
echo "Generating ground truth..."

# 1. Create Data content
# Note: "http" filter includes both requests and responses
tshark -r "$PCAP_FILE" \
    -Y "http" \
    -T fields \
    -E separator=, \
    -E quote=d \
    -e frame.number \
    -e frame.time_relative \
    -e ip.src \
    -e ip.dst \
    -e http.request.method \
    -e http.request.uri \
    -e http.host \
    -e http.response.code \
    -e http.content_type \
    -e frame.len \
    > "$GT_DIR/ground_truth_data.csv"

# 2. Count packets
GT_COUNT=$(wc -l < "$GT_DIR/ground_truth_data.csv")
echo "$GT_COUNT" > "$GT_DIR/packet_count.txt"

# 3. Create full ground truth with header for strict comparison
HEADER="frame_number,time_relative,source_ip,destination_ip,http_method,http_request_uri,http_host,http_response_code,http_content_type,frame_length"
echo "$HEADER" > "$GT_DIR/ground_truth_full.csv"
cat "$GT_DIR/ground_truth_data.csv" >> "$GT_DIR/ground_truth_full.csv"

chmod -R 700 "$GT_DIR"
chown -R root:root "$GT_DIR"

echo "Ground truth generated: $GT_COUNT records"

# Open a terminal for the user since this is a CLI task
echo "Opening terminal..."
su - ga -c "DISPLAY=:1 x-terminal-emulator -geometry 100x30 &"
sleep 2
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="