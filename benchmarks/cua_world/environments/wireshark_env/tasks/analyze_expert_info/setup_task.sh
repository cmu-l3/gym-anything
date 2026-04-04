#!/bin/bash
set -e
echo "=== Setting up Expert Info Analysis task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Verify the capture file exists and is readable
PCAP_FILE="/home/ga/Documents/captures/200722_tcp_anon.pcapng"
if [ ! -s "$PCAP_FILE" ]; then
    echo "ERROR: Capture file not found at $PCAP_FILE"
    # Try to re-download if missing (using script from env setup)
    if [ -f /workspace/scripts/install_wireshark.sh ]; then
        # Minimal download attempt
        wget -q -O "$PCAP_FILE" "https://wiki.wireshark.org/uploads/1894ec2950fd0e1bfbdac49b3de0bc92/200722_tcp_anon.pcapng" || true
    fi
    if [ ! -s "$PCAP_FILE" ]; then
        echo "CRITICAL: Failed to locate or download PCAP file."
        exit 1
    fi
fi

# Pre-compute ground truth using tshark (hidden from agent)
GROUND_TRUTH_DIR="/var/lib/wireshark_ground_truth"
mkdir -p "$GROUND_TRUTH_DIR"
chmod 700 "$GROUND_TRUTH_DIR"  # Restrict access

echo "Computing ground truth..."

# 1. Extract all expert info entries with severity and message
tshark -r "$PCAP_FILE" -Y "_ws.expert" -T fields \
    -e _ws.expert.severity -e _ws.expert.message 2>/dev/null \
    > "$GROUND_TRUTH_DIR/expert_raw.txt" || true

# 2. Compute severity counts
ERROR_COUNT=$(grep -ci "^error" "$GROUND_TRUTH_DIR/expert_raw.txt" 2>/dev/null || echo "0")
WARN_COUNT=$(grep -ci "^warning" "$GROUND_TRUTH_DIR/expert_raw.txt" 2>/dev/null || echo "0")
NOTE_COUNT=$(grep -ci "^note" "$GROUND_TRUTH_DIR/expert_raw.txt" 2>/dev/null || echo "0")
CHAT_COUNT=$(grep -ci "^chat" "$GROUND_TRUTH_DIR/expert_raw.txt" 2>/dev/null || echo "0")
TOTAL_COUNT=$((ERROR_COUNT + WARN_COUNT + NOTE_COUNT + CHAT_COUNT))

# 3. Get unique message types and top messages
# Normalize whitespace and get counts
cut -f2 "$GROUND_TRUTH_DIR/expert_raw.txt" | sort | uniq -c | sort -rn > "$GROUND_TRUTH_DIR/message_counts.txt"

# Count unique lines
UNIQUE_TYPES=$(wc -l < "$GROUND_TRUTH_DIR/message_counts.txt" | tr -d ' ')

# Save ground truth as JSON for the verifier
# We also save the top 5 messages as a JSON array
cat > "$GROUND_TRUTH_DIR/ground_truth.json" << GTEOF
{
    "errors": $ERROR_COUNT,
    "warnings": $WARN_COUNT,
    "notes": $NOTE_COUNT,
    "chats": $CHAT_COUNT,
    "total": $TOTAL_COUNT,
    "unique_types": $UNIQUE_TYPES
}
GTEOF

# Clean up any previous report from agent
rm -f /home/ga/Documents/captures/expert_info_report.txt 2>/dev/null || true

# Ensure Wireshark is running (empty, no file loaded as per Starting State)
if ! pgrep -f wireshark > /dev/null; then
    echo "Starting Wireshark..."
    su - ga -c "DISPLAY=:1 wireshark &"
    sleep 5
fi

# Wait for Wireshark window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "wireshark"; then
        echo "Wireshark window detected"
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Wireshark" 2>/dev/null || true

# Dismiss any startup dialogs/Welcome screen focus
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "Ground truth computed: Errors=$ERROR_COUNT, Warnings=$WARN_COUNT"
echo "=== Expert Info Analysis task setup complete ==="