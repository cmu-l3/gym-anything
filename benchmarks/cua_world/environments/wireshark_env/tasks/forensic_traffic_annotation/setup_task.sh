#!/bin/bash
set -e

echo "=== Setting up forensic_traffic_annotation task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up previous artifacts
rm -f /home/ga/Documents/captures/evidence_annotated.pcapng 2>/dev/null || true
rm -f /tmp/ground_truth.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

PCAP_FILE="/home/ga/Documents/captures/200722_tcp_anon.pcapng"

if [ ! -f "$PCAP_FILE" ]; then
    echo "ERROR: Input PCAP file not found: $PCAP_FILE"
    exit 1
fi

# Calculate Ground Truth: Identify the TCP stream with max bytes
# We use a small embedded python script to process tshark output efficiently
echo "Calculating ground truth statistics..."

python3 -c "
import subprocess
import json
import sys
from collections import defaultdict

pcap_file = '$PCAP_FILE'

# Get tcp.stream and frame.len for all TCP packets
cmd = ['tshark', '-r', pcap_file, '-T', 'fields', '-e', 'tcp.stream', '-e', 'frame.len']
try:
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    
    stream_bytes = defaultdict(int)
    stream_packets = defaultdict(int)
    
    for line in result.stdout.splitlines():
        parts = line.strip().split()
        if len(parts) >= 2:
            try:
                # Some packets might not have tcp.stream set, skip them
                sid = int(parts[0])
                length = int(parts[1])
                stream_bytes[sid] += length
                stream_packets[sid] += 1
            except ValueError:
                continue

    if not stream_bytes:
        print(json.dumps({'error': 'No TCP streams found'}))
        sys.exit(1)

    # Find stream with max bytes
    best_sid = max(stream_bytes, key=stream_bytes.get)
    
    gt = {
        'target_stream_id': best_sid,
        'target_bytes': stream_bytes[best_sid],
        'target_packet_count': stream_packets[best_sid]
    }
    
    with open('/tmp/ground_truth.json', 'w') as f:
        json.dump(gt, f)
        
    print(f'Ground Truth Calculated: Stream {best_sid} with {stream_bytes[best_sid]} bytes')

except Exception as e:
    print(f'Error calculating ground truth: {e}')
    sys.exit(1)
"

# Open Wireshark with the capture file
echo "Starting Wireshark..."
su - ga -c "DISPLAY=:1 wireshark '$PCAP_FILE' > /dev/null 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Wireshark"; then
        echo "Wireshark window detected"
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Wireshark" 2>/dev/null || true

# Initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="