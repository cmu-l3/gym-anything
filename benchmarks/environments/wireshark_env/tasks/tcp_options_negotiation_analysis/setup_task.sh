#!/bin/bash
set -e
echo "=== Setting up TCP Options Negotiation Analysis task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Source shared utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

PCAP_FILE="/home/ga/Documents/captures/200722_tcp_anon.pcapng"

# Verify capture file exists
if [ ! -s "$PCAP_FILE" ]; then
    echo "ERROR: Required capture file not found: $PCAP_FILE"
    exit 1
fi

# ------------------------------------------------------------------
# GENERATE GROUND TRUTH (Hidden from agent)
# ------------------------------------------------------------------
GROUND_TRUTH_DIR="/var/lib/wireshark_ground_truth"
mkdir -p "$GROUND_TRUTH_DIR"

echo "Generating ground truth data..."

# 1. SYN Packet Count
# Filter: SYN=1, ACK=0
SYN_COUNT=$(tshark -r "$PCAP_FILE" -Y "tcp.flags.syn==1 && tcp.flags.ack==0" 2>/dev/null | wc -l)
echo "$SYN_COUNT" > "$GROUND_TRUTH_DIR/syn_count.txt"

# 2. Raw Data for Verification (Frame, IPs, Ports, Options)
# We export fields to a CSV for the verifier to compare against
tshark -r "$PCAP_FILE" -Y "tcp.flags.syn==1 && tcp.flags.ack==0" \
    -T fields -E separator=, -E quote=d \
    -e frame.number \
    -e ip.src -e ip.dst \
    -e tcp.srcport -e tcp.dstport \
    -e tcp.options.mss_val \
    -e tcp.options.wscale.shift \
    -e tcp.options.sack_perm \
    -e tcp.options.timestamp.tsval \
    -e tcp.window_size_value \
    2>/dev/null > "$GROUND_TRUTH_DIR/ground_truth_syns.csv"

# 3. Summary Statistics
# Unique MSS values (sorted, comma separated)
tshark -r "$PCAP_FILE" -Y "tcp.flags.syn==1 && tcp.flags.ack==0" -T fields -e tcp.options.mss_val 2>/dev/null | \
    sort -n | uniq | grep -v '^$' | paste -sd "," - > "$GROUND_TRUTH_DIR/unique_mss.txt"

# Unique Window Scale values
tshark -r "$PCAP_FILE" -Y "tcp.flags.syn==1 && tcp.flags.ack==0" -T fields -e tcp.options.wscale.shift 2>/dev/null | \
    sort -n | uniq | grep -v '^$' | paste -sd "," - > "$GROUND_TRUTH_DIR/unique_wscale.txt"

# SACK Permitted Count
SACK_COUNT=$(tshark -r "$PCAP_FILE" -Y "tcp.flags.syn==1 && tcp.flags.ack==0 && tcp.options.sack_perm" 2>/dev/null | wc -l)
echo "$SACK_COUNT" > "$GROUND_TRUTH_DIR/sack_count.txt"

# Timestamp Present Count
TS_COUNT=$(tshark -r "$PCAP_FILE" -Y "tcp.flags.syn==1 && tcp.flags.ack==0 && tcp.options.timestamp.tsval" 2>/dev/null | wc -l)
echo "$TS_COUNT" > "$GROUND_TRUTH_DIR/ts_count.txt"

# Most Common MSS
tshark -r "$PCAP_FILE" -Y "tcp.flags.syn==1 && tcp.flags.ack==0" -T fields -e tcp.options.mss_val 2>/dev/null | \
    sort | uniq -c | sort -rn | head -1 | awk '{print $2}' > "$GROUND_TRUTH_DIR/most_common_mss.txt"

# Most Common Dest Port
tshark -r "$PCAP_FILE" -Y "tcp.flags.syn==1 && tcp.flags.ack==0" -T fields -e tcp.dstport 2>/dev/null | \
    sort | uniq -c | sort -rn | head -1 | awk '{print $2}' > "$GROUND_TRUTH_DIR/most_common_dst_port.txt"

# Secure the ground truth directory
chmod -R 700 "$GROUND_TRUTH_DIR"
chown -R root:root "$GROUND_TRUTH_DIR"

# ------------------------------------------------------------------
# SETUP UI
# ------------------------------------------------------------------

# Remove previous output files if they exist
rm -f /home/ga/Documents/tcp_options_report.csv
rm -f /home/ga/Documents/tcp_options_summary.txt

# Start Wireshark with the capture file
echo "Starting Wireshark..."
su - ga -c "DISPLAY=:1 wireshark '$PCAP_FILE' > /dev/null 2>&1 &"

# Wait for Wireshark window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Wireshark" > /dev/null; then
        echo "Wireshark started."
        break
    fi
    sleep 1
done

# Maximize Wireshark
DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "Wireshark" 2>/dev/null || true

# Wait a moment for UI to settle
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="