#!/bin/bash
set -e
echo "=== Setting up I/O Statistics Timeline task ==="
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Verify the capture file exists
PCAP="/home/ga/Documents/captures/200722_tcp_anon.pcapng"
if [ ! -s "$PCAP" ]; then
    echo "ERROR: Capture file missing: $PCAP"
    exit 1
fi

# Remove any pre-existing report (clean state)
rm -f /home/ga/Documents/captures/io_stats_report.txt

# Create ground truth directory (hidden from agent)
GROUND_TRUTH_DIR="/var/lib/wireshark_ground_truth"
rm -rf "$GROUND_TRUTH_DIR"
mkdir -p "$GROUND_TRUTH_DIR"

echo "Computing ground truth..."

# 1. Total Packets
TOTAL_PACKETS=$(tshark -r "$PCAP" 2>/dev/null | wc -l)
echo "$TOTAL_PACKETS" > "$GROUND_TRUTH_DIR/total_packets.txt"

# 2. Capture Duration (last packet time relative)
LAST_TIME=$(tshark -r "$PCAP" -T fields -e frame.time_relative 2>/dev/null | tail -1 | xargs)
echo "$LAST_TIME" > "$GROUND_TRUTH_DIR/capture_duration.txt"

# 3. Total Bytes
TOTAL_BYTES=$(tshark -r "$PCAP" -T fields -e frame.len 2>/dev/null | awk '{s+=$1} END {print s}')
echo "$TOTAL_BYTES" > "$GROUND_TRUTH_DIR/total_bytes.txt"

# 4. Avg PPS
python3 -c "
tp = int('$TOTAL_PACKETS')
dur = float('$LAST_TIME')
print(f'{tp/dur:.1f}')
" > "$GROUND_TRUTH_DIR/avg_pps.txt"

# 5. Busiest Interval (1-second bins)
# We run tshark io,stat and parse it
tshark -r "$PCAP" -q -z io,stat,1 2>/dev/null > "$GROUND_TRUTH_DIR/io_stat_raw.txt"

python3 << 'PYEOF'
import re, os

gt_dir = "/var/lib/wireshark_ground_truth"
try:
    with open(os.path.join(gt_dir, "io_stat_raw.txt")) as f:
        lines = f.readlines()
    
    max_frames = -1
    max_start = 0.0
    
    # Regex to match lines like: | 0.000 <> 1.000 | 123 | 45678 |
    # or simple variations depending on tshark version
    for line in lines:
        if "<>" in line and "|" in line:
            parts = line.split("|")
            if len(parts) >= 4:
                # time_range part: " 0.000 <> 1.000 "
                time_range = parts[1].strip()
                frames_str = parts[2].strip()
                
                if "<>" in time_range:
                    start_str = time_range.split("<>")[0].strip()
                    try:
                        frames = int(frames_str)
                        start = float(start_str)
                        if frames > max_frames:
                            max_frames = frames
                            max_start = start
                    except ValueError:
                        continue

    with open(os.path.join(gt_dir, "busiest_start.txt"), "w") as f:
        f.write(f"{max_start:.1f}\n")
    with open(os.path.join(gt_dir, "busiest_packets.txt"), "w") as f:
        f.write(f"{max_frames}\n")
        
except Exception as e:
    print(f"Error parsing IO stats: {e}")
PYEOF

# Secure the ground truth directory
chmod 700 "$GROUND_TRUTH_DIR"
chmod 600 "$GROUND_TRUTH_DIR"/*.txt

# Start Wireshark
if ! pgrep -f "wireshark" > /dev/null 2>&1; then
    echo "Starting Wireshark..."
    su - ga -c "DISPLAY=:1 wireshark &" &
    sleep 5
fi

# Wait for Wireshark window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "wireshark"; then
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss any dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="