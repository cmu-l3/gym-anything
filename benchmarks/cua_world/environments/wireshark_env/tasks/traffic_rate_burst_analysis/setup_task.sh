#!/bin/bash
set -e

echo "=== Setting up Traffic Rate Analysis Task ==="

# 1. Source utilities
source /workspace/scripts/task_utils.sh

# 2. Record Start Time for Anti-Gaming
date +%s > /tmp/task_start_time.txt

# 3. Clean previous artifacts
rm -f /home/ga/Documents/traffic_rate_report.txt
rm -f /tmp/task_result.json
mkdir -p /var/lib/wireshark

# 4. Verify PCAP exists
PCAP_FILE="/home/ga/Documents/captures/200722_tcp_anon.pcapng"
if [ ! -f "$PCAP_FILE" ]; then
    echo "ERROR: PCAP file not found at $PCAP_FILE"
    exit 1
fi

# 5. Pre-compute Ground Truth (Hidden from Agent)
echo "Computing ground truth statistics..."

# We use python to accurately compute the bins exactly as requested
python3 -c "
import sys
import json
import subprocess
import math

pcap_path = '$PCAP_FILE'

# Get all frame timestamps
cmd = ['tshark', '-r', pcap_path, '-T', 'fields', '-e', 'frame.time_epoch']
result = subprocess.run(cmd, capture_output=True, text=True)

timestamps = []
for line in result.stdout.strip().split('\n'):
    if line.strip():
        timestamps.append(float(line.strip()))

timestamps.sort()

if not timestamps:
    print('Error: No packets found')
    sys.exit(1)

first_ts = timestamps[0]
last_ts = timestamps[-1]
# Duration as floor of difference
duration = int(math.floor(last_ts - first_ts))
if duration == 0: duration = 1 # Safety for extremely short captures

# Binning
bins = [0] * duration
for ts in timestamps:
    offset = int(math.floor(ts - first_ts))
    if offset < 0: offset = 0
    if offset >= duration: offset = duration - 1
    bins[offset] += 1

total_packets = len(timestamps)
avg_pps = round(total_packets / duration, 2)
peak_pps = max(bins)
peak_second = bins.index(peak_pps)
idle_seconds = bins.count(0)
burst_threshold = int(math.floor(avg_pps * 2))
burst_count = sum(1 for x in bins if x >= burst_threshold)

ground_truth = {
    'CAPTURE_DURATION_SECS': duration,
    'TOTAL_PACKETS': total_packets,
    'AVERAGE_PPS': avg_pps,
    'PEAK_PPS': peak_pps,
    'PEAK_SECOND': peak_second,
    'IDLE_SECONDS': idle_seconds,
    'BURST_THRESHOLD': burst_threshold,
    'BURST_COUNT': burst_count,
    'bins': bins
}

with open('/var/lib/wireshark/ground_truth.json', 'w') as f:
    json.dump(ground_truth, f)

print(f'Ground truth computed: {total_packets} pkts, {duration}s duration')
"

chmod 600 /var/lib/wireshark/ground_truth.json

# 6. Open Wireshark with the file
echo "Starting Wireshark..."
su - ga -c "DISPLAY=:1 wireshark '$PCAP_FILE' > /dev/null 2>&1 &"

# 7. Wait for window and maximize
sleep 5
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "wireshark"; then
        echo "Wireshark window detected."
        # Maximize
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
        break
    fi
    sleep 1
done

# 8. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="