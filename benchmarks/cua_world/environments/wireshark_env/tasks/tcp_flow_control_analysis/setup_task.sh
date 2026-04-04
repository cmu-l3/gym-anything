#!/bin/bash
set -euo pipefail

echo "=== Setting up TCP Flow Control Analysis task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure the PCAP file exists
PCAP_FILE="/home/ga/Documents/captures/200722_tcp_anon.pcapng"
if [ ! -f "$PCAP_FILE" ]; then
    echo "ERROR: PCAP file not found at $PCAP_FILE"
    # Try to re-download if missing (using the logic from install_wireshark.sh if needed, 
    # but strictly we expect the env to have it. We'll fail if not.)
    exit 1
fi

# Clean up any previous report
REPORT_FILE="/home/ga/Documents/captures/flow_control_report.txt"
rm -f "$REPORT_FILE" 2>/dev/null || true

# Pre-calculate ground truth values to a hidden file 
# (This ensures we have a baseline even if the file gets modified, though unlikely for PCAP)
# We store them in a secure location the agent isn't expected to look
GT_DIR="/var/lib/wireshark/ground_truth"
mkdir -p "$GT_DIR"

echo "Calculating ground truth (this may take a few seconds)..."

# 1. Total Packets
tshark -r "$PCAP_FILE" 2>/dev/null | wc -l > "$GT_DIR/total_packets"

# 2. Zero Window
tshark -r "$PCAP_FILE" -Y "tcp.analysis.zero_window" 2>/dev/null | wc -l > "$GT_DIR/zero_window"

# 3. Window Update
tshark -r "$PCAP_FILE" -Y "tcp.analysis.window_update" 2>/dev/null | wc -l > "$GT_DIR/window_update"

# 4. Window Full
tshark -r "$PCAP_FILE" -Y "tcp.analysis.window_full" 2>/dev/null | wc -l > "$GT_DIR/window_full"

# 5. Max Window Size (raw)
tshark -r "$PCAP_FILE" -T fields -e tcp.window_size_value 2>/dev/null | sort -rn | head -1 > "$GT_DIR/max_window"

# 6. Min Non-Zero Window Size (raw)
tshark -r "$PCAP_FILE" -Y "tcp.window_size_value > 0" -T fields -e tcp.window_size_value 2>/dev/null | sort -n | head -1 > "$GT_DIR/min_window"

# 7. Unique Conversations
tshark -r "$PCAP_FILE" -q -z conv,tcp 2>/dev/null | grep "<->" | wc -l > "$GT_DIR/conversations"

# 8. SYN with Window Scale
tshark -r "$PCAP_FILE" -Y "tcp.flags.syn==1 && tcp.options.wscale" 2>/dev/null | wc -l > "$GT_DIR/syn_wscale"

# Ensure Wireshark is not running initially
pkill -f wireshark 2>/dev/null || true

# Prepare desktop (close windows, show desktop)
wmctrl -k on 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="