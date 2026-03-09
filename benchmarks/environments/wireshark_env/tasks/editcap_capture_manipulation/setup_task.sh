#!/bin/bash
set -e
echo "=== Setting up editcap capture manipulation task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

SOURCE_PCAP="/home/ga/Documents/captures/200722_tcp_anon.pcapng"

# Verify source file exists
if [ ! -s "$SOURCE_PCAP" ]; then
    echo "ERROR: Source capture file not found: $SOURCE_PCAP"
    exit 1
fi

# Clean up any previous run
rm -rf /home/ga/Documents/captures/output
mkdir -p /home/ga/Documents/captures/output
# Ensure the user has permissions, but keep directory empty initially
chown ga:ga /home/ga/Documents/captures/output

echo "Computing ground truth values..."

# 1. Original Count
ORIG_COUNT=$(tshark -r "$SOURCE_PCAP" 2>/dev/null | wc -l)
echo "Original Count: $ORIG_COUNT"

# 2. Timestamps
# First packet timestamp (for first_100 and timeshift verification)
FIRST_TS=$(tshark -r "$SOURCE_PCAP" -T fields -e frame.time_epoch -c 1 2>/dev/null | head -1)

# Packet #50 timestamp (for range verification)
# sed -n '50p' gets the 50th line
PKT50_TS=$(tshark -r "$SOURCE_PCAP" -T fields -e frame.time_epoch 2>/dev/null | sed -n '50p')

echo "First TS: $FIRST_TS"
echo "Pkt 50 TS: $PKT50_TS"

# 3. Dedup Count (Simulate the expected dedup)
# We use a temp file in /tmp so the agent doesn't see it
DEDUP_GT_FILE="/tmp/gt_deduped.pcapng"
editcap -d -w 5 "$SOURCE_PCAP" "$DEDUP_GT_FILE" 2>/dev/null || true
DEDUP_COUNT=$(tshark -r "$DEDUP_GT_FILE" 2>/dev/null | wc -l)
rm -f "$DEDUP_GT_FILE"
echo "Dedup Count: $DEDUP_COUNT"

# Store ground truth in a hidden JSON for export_result.sh to use
cat > /tmp/task_ground_truth.json << EOF
{
    "original_count": $ORIG_COUNT,
    "first_timestamp": "$FIRST_TS",
    "packet_50_timestamp": "$PKT50_TS",
    "dedup_count": $DEDUP_COUNT,
    "source_file": "$SOURCE_PCAP"
}
EOF
chmod 600 /tmp/task_ground_truth.json

# Open a terminal for the agent since this is a CLI task
echo "Opening terminal..."
su - ga -c "DISPLAY=:1 xterm -geometry 100x30+50+50 -title 'Terminal - Task' &"

# Wait for window
sleep 2
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="