#!/bin/bash
set -e

echo "=== Setting up Packet Size Distribution Analysis task ==="

# 1. Record task start time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous artifacts
rm -f /home/ga/Documents/captures/packet_size_report.txt
rm -rf /var/lib/wireshark_ground_truth
mkdir -p /var/lib/wireshark_ground_truth
chmod 700 /var/lib/wireshark_ground_truth

# 3. Verify PCAP availability
PCAP_PATH="/home/ga/Documents/captures/200722_tcp_anon.pcapng"
if [ ! -f "$PCAP_PATH" ]; then
    echo "ERROR: Capture file not found at $PCAP_PATH"
    # Try to copy from common location if missing
    if [ -f "/usr/share/doc/wireshark-common/captures/200722_tcp_anon.pcapng" ]; then
        cp "/usr/share/doc/wireshark-common/captures/200722_tcp_anon.pcapng" "$PCAP_PATH"
    else
        # Critical failure if file missing
        echo "CRITICAL: Could not locate 200722_tcp_anon.pcapng"
        exit 1
    fi
fi
chmod 644 "$PCAP_PATH"

# 4. Compute Ground Truth (Hidden from Agent)
echo "Computing ground truth statistics..."

# Extract all frame lengths to a temp file
tshark -r "$PCAP_PATH" -T fields -e frame.len > /tmp/lengths.txt

# Use Python to compute exact stats and buckets to ensure accuracy
python3 << 'PYEOF'
import json
import statistics

# Read lengths
with open("/tmp/lengths.txt", "r") as f:
    lengths = [int(line.strip()) for line in f if line.strip().isdigit()]

if not lengths:
    print("Error: No packets found")
    exit(1)

total = len(lengths)
min_size = min(lengths)
max_size = max(lengths)
avg_size = round(statistics.mean(lengths))

# Define buckets
buckets = {
    "0-79": 0,
    "80-159": 0,
    "160-319": 0,
    "320-639": 0,
    "640-1279": 0,
    "1280-2559": 0
}

for l in lengths:
    if l <= 79: buckets["0-79"] += 1
    elif l <= 159: buckets["80-159"] += 1
    elif l <= 319: buckets["160-319"] += 1
    elif l <= 639: buckets["320-639"] += 1
    elif l <= 1279: buckets["640-1279"] += 1
    elif l <= 2559: buckets["1280-2559"] += 1

# Calculate percentages and dominant
bucket_stats = {}
max_count = -1
dominant_range = ""

for k, v in buckets.items():
    pct = round((v / total) * 100, 1) if total > 0 else 0
    bucket_stats[k] = {"count": v, "percent": pct}
    if v > max_count:
        max_count = v
        dominant_range = k

ground_truth = {
    "total": total,
    "min": min_size,
    "max": max_size,
    "avg": avg_size,
    "buckets": bucket_stats,
    "dominant_bucket": dominant_range,
    "dominant_count": max_count
}

with open("/var/lib/wireshark_ground_truth/ground_truth.json", "w") as f:
    json.dump(ground_truth, f, indent=2)

print(f"Ground truth calculated: Total={total}, Dominant={dominant_range}")
PYEOF

# Cleanup temp length file
rm -f /tmp/lengths.txt

# 5. Launch Wireshark
echo "Starting Wireshark..."
if ! pgrep -f "wireshark" > /dev/null; then
    su - ga -c "DISPLAY=:1 wireshark '$PCAP_PATH' > /dev/null 2>&1 &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "wireshark"; then
            echo "Wireshark window detected"
            break
        fi
        sleep 1
    done
fi

# Maximize window
DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Wireshark" 2>/dev/null || true

# Dismiss potential "Welcome" or "Software Update" dialogs
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 6. Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="