#!/bin/bash
set -e
echo "=== Setting up TCP Conversation Profiling task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

PCAP_FILE="/home/ga/Documents/captures/200722_tcp_anon.pcapng"

# Verify required capture file exists
if [ ! -s "$PCAP_FILE" ]; then
    echo "ERROR: Required capture file not found: $PCAP_FILE"
    # Try to download if missing (using task_utils logic or direct wget)
    wget -q -O "$PCAP_FILE" "https://wiki.wireshark.org/uploads/1894ec2950fd0e1bfbdac49b3de0bc92/200722_tcp_anon.pcapng" || true
fi

if [ ! -s "$PCAP_FILE" ]; then
    echo "FATAL: Could not locate or download capture file."
    exit 1
fi

# Clean up any previous task output
rm -f /home/ga/Documents/captures/tcp_conversation_report.txt
rm -f /home/ga/Documents/captures/tcp_conversations.csv
rm -f /tmp/task_result.json

# Precompute ground truth using tshark (hidden from agent)
GROUND_TRUTH_DIR="/var/lib/wireshark_ground_truth"
mkdir -p "$GROUND_TRUTH_DIR"
chmod 700 "$GROUND_TRUTH_DIR"

echo "Computing ground truth statistics..."

# Get raw conversation stats
# Output format of tshark -z conv,tcp:
# Filter:<filter>
#                                               |       <-      | |       ->      | |     Total     |    Relative    |   Duration   |
#                                               | Frames  Bytes | | Frames  Bytes | | Frames  Bytes |      Start     |              |
# 192.168.0.1:12345    <-> 10.0.0.1:80              50    3000   100    40000     150    43000         0.0000         5.5000
tshark -r "$PCAP_FILE" -q -z conv,tcp 2>/dev/null > "$GROUND_TRUTH_DIR/conv_raw.txt"

# 1. Total Count
# Count lines containing "<->"
CONV_COUNT=$(grep "<->" "$GROUND_TRUTH_DIR/conv_raw.txt" | wc -l)
echo "$CONV_COUNT" > "$GROUND_TRUTH_DIR/total_conversations.txt"

# 2. Longest Duration
# Duration is the last column ($NF)
LONGEST_LINE=$(grep "<->" "$GROUND_TRUTH_DIR/conv_raw.txt" | awk '{print $NF, $0}' | sort -rn | head -1 | cut -d' ' -f2-)
LONGEST_DURATION=$(echo "$LONGEST_LINE" | awk '{print $NF}')
LONGEST_ADDR_A=$(echo "$LONGEST_LINE" | awk '{print $1}')
LONGEST_ADDR_B=$(echo "$LONGEST_LINE" | awk '{print $3}')
echo "${LONGEST_ADDR_A} ${LONGEST_ADDR_B} ${LONGEST_DURATION}" > "$GROUND_TRUTH_DIR/longest_duration.txt"

# 3. Highest Volume
# Total bytes is typically the 3rd field from the end (before rel_start and duration)
# Fields: A <-> B, fA, bA, fB, bB, fTotal, bTotal, Start, Dur
HIGHEST_LINE=$(grep "<->" "$GROUND_TRUTH_DIR/conv_raw.txt" | awk '{
    n = NF;
    total_bytes = $(n-2);
    print total_bytes, $0;
}' | sort -rn | head -1 | cut -d' ' -f2-)
HIGHEST_BYTES=$(echo "$HIGHEST_LINE" | awk '{n=NF; print $(n-2)}')
HIGHEST_ADDR_A=$(echo "$HIGHEST_LINE" | awk '{print $1}')
HIGHEST_ADDR_B=$(echo "$HIGHEST_LINE" | awk '{print $3}')
echo "${HIGHEST_ADDR_A} ${HIGHEST_ADDR_B} ${HIGHEST_BYTES}" > "$GROUND_TRUTH_DIR/highest_volume.txt"

# 4. Average Duration
AVG_DURATION=$(grep "<->" "$GROUND_TRUTH_DIR/conv_raw.txt" | awk '{sum += $NF; count++} END {if(count>0) printf "%.2f", sum/count; else print "0.00"}')
echo "$AVG_DURATION" > "$GROUND_TRUTH_DIR/average_duration.txt"

echo "Ground truth computed: $CONV_COUNT conversations."

# Ensure Wireshark is not already running
pkill -f wireshark 2>/dev/null || true
sleep 2

# Launch Wireshark with the capture file
echo "Launching Wireshark..."
su - ga -c "DISPLAY=:1 wireshark '$PCAP_FILE' > /dev/null 2>&1 &"

# Wait for Wireshark window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "wireshark"; then
        break
    fi
    sleep 1
done

# Maximize and focus Wireshark
sleep 2
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 xdotool key Escape 2>/dev/null || true  # Dismiss any "Update available" dialogs
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="