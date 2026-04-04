#!/bin/bash
set -e

echo "=== Setting up merge_and_analyze_captures task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Directories
CAP_DIR="/home/ga/Documents/captures"
DNS_CAP="$CAP_DIR/dns.cap"
HTTP_CAP="$CAP_DIR/http.cap"

# Verify input files exist
if [ ! -f "$DNS_CAP" ] || [ ! -f "$HTTP_CAP" ]; then
    echo "ERROR: Input capture files missing!"
    exit 1
fi

# Clean up previous artifacts
rm -f "$CAP_DIR/merged_traffic.pcapng" 2>/dev/null || true
rm -f "$CAP_DIR/merge_report.txt" 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Calculate Ground Truth for verification
echo "Calculating ground truth metrics..."

# 1. Packet Counts
DNS_COUNT=$(tshark -r "$DNS_CAP" 2>/dev/null | wc -l)
HTTP_COUNT=$(tshark -r "$HTTP_CAP" 2>/dev/null | wc -l)
EXPECTED_TOTAL=$((DNS_COUNT + HTTP_COUNT))

# 2. Time Range (Start/End)
# We use tshark to get the first and last timestamps from both files to find global min/max
# Format: epoch time for easy comparison
DNS_START=$(tshark -r "$DNS_CAP" -T fields -e frame.time_epoch -c 1 2>/dev/null)
DNS_END=$(tshark -r "$DNS_CAP" -T fields -e frame.time_epoch 2>/dev/null | tail -n 1)

HTTP_START=$(tshark -r "$HTTP_CAP" -T fields -e frame.time_epoch -c 1 2>/dev/null)
HTTP_END=$(tshark -r "$HTTP_CAP" -T fields -e frame.time_epoch 2>/dev/null | tail -n 1)

# Find absolute start (min) and end (max)
# Bash floating point comparison trick
ACTUAL_START=$(python3 -c "print(min($DNS_START, $HTTP_START))")
ACTUAL_END=$(python3 -c "print(max($DNS_END, $HTTP_END))")

# Save ground truth to temp file for export script
cat > /tmp/ground_truth.json << EOF
{
    "dns_count": $DNS_COUNT,
    "http_count": $HTTP_COUNT,
    "expected_total": $EXPECTED_TOTAL,
    "start_epoch": $ACTUAL_START,
    "end_epoch": $ACTUAL_END
}
EOF

echo "Ground Truth: Total=$EXPECTED_TOTAL, Start=$ACTUAL_START, End=$ACTUAL_END"

# Ensure Wireshark is running and ready
if ! pgrep -f "wireshark" > /dev/null; then
    echo "Starting Wireshark..."
    su - ga -c "DISPLAY=:1 wireshark > /dev/null 2>&1 &"
    sleep 5
fi

# Maximize Wireshark window
DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Wireshark" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="