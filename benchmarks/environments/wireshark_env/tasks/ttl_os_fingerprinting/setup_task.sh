#!/bin/bash
set -e
echo "=== Setting up TTL OS Fingerprinting task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean any previous task output
rm -f /home/ga/Documents/captures/ttl_fingerprint_report.csv
rm -f /home/ga/Documents/captures/ttl_fingerprint_summary.txt
rm -rf /tmp/ttl_ground_truth

# Verify all capture files exist
echo "Checking capture files..."
MISSING=0
for f in http.cap dns.cap smtp.pcap telnet-cooked.pcap 200722_tcp_anon.pcapng; do
    if [ ! -s "/home/ga/Documents/captures/$f" ]; then
        echo "ERROR: Missing capture file: $f"
        MISSING=$((MISSING + 1))
    else
        echo "  OK: $f"
    fi
done

if [ "$MISSING" -gt 0 ]; then
    echo "WARNING: $MISSING capture file(s) missing. Task may not be fully solvable."
fi

# Compute and store ground truth (hidden from agent)
echo "Computing ground truth..."
GROUND_TRUTH_DIR="/tmp/ttl_ground_truth"
mkdir -p "$GROUND_TRUTH_DIR"
chmod 700 "$GROUND_TRUTH_DIR"

# Extract all (src_ip, ttl) pairs from all captures using tshark
> "$GROUND_TRUTH_DIR/raw_ttl_data.txt"
for f in /home/ga/Documents/captures/*.cap /home/ga/Documents/captures/*.pcap /home/ga/Documents/captures/*.pcapng; do
    if [ -f "$f" ]; then
        tshark -r "$f" -T fields -e ip.src -e ip.ttl 2>/dev/null | grep -v "^$" >> "$GROUND_TRUTH_DIR/raw_ttl_data.txt" || true
    fi
done

# Compute mode TTL per unique IP and classify using Python
# This generates the reference CSV and Summary
python3 << 'PYEOF'
import csv
from collections import Counter, defaultdict

raw_file = "/tmp/ttl_ground_truth/raw_ttl_data.txt"
gt_csv = "/tmp/ttl_ground_truth/ground_truth.csv"
gt_stats = "/tmp/ttl_ground_truth/ground_truth_stats.json"

ip_ttls = defaultdict(list)
with open(raw_file) as f:
    for line in f:
        parts = line.strip().split('\t')
        if len(parts) >= 2 and parts[0] and parts[1]:
            # Handle multiple IPs in one packet (tunneling) - take the first (outer)
            ip = parts[0].split(',')[0].strip()
            ttl_str = parts[1].split(',')[0].strip()
            try:
                ttl = int(ttl_str)
                if ip and ttl > 0:
                    ip_ttls[ip].append(ttl)
            except ValueError:
                continue

def get_initial_ttl(observed):
    for default in [32, 64, 128, 255]:
        if observed <= default:
            return default
    return 255

def get_os_family(initial_ttl):
    mapping = {32: "Windows-9x", 64: "Linux/Unix", 128: "Windows", 255: "Cisco/Solaris"}
    return mapping.get(initial_ttl, "Unknown")

results = []
for ip in sorted(ip_ttls.keys()):
    ttl_counts = Counter(ip_ttls[ip])
    mode_ttl = ttl_counts.most_common(1)[0][0]
    initial = get_initial_ttl(mode_ttl)
    hop_count = initial - mode_ttl
    os_family = get_os_family(initial)
    results.append({
        'ip': ip,
        'observed_ttl': mode_ttl,
        'initial_ttl': initial,
        'hop_count': hop_count,
        'os_family': os_family
    })

# Write ground truth CSV
with open(gt_csv, 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['ip', 'observed_ttl', 'initial_ttl', 'hop_count', 'os_family'])
    writer.writeheader()
    writer.writerows(results)

# Calculate stats
import json
os_counts = Counter(r['os_family'] for r in results)
if results:
    max_hop = max(results, key=lambda r: r['hop_count'])
    min_hop = min(results, key=lambda r: r['hop_count'])
    
    stats = {
        "total_ips": len(results),
        "os_counts": dict(os_counts),
        "max_hop_ip": max_hop['ip'],
        "max_hop_val": max_hop['hop_count'],
        "min_hop_ip": min_hop['ip'],
        "min_hop_val": min_hop['hop_count']
    }
else:
    stats = {"total_ips": 0}

with open(gt_stats, 'w') as f:
    json.dump(stats, f, indent=2)

print(f"Ground truth generated: {len(results)} unique IPs")
PYEOF

# Ensure Wireshark is running
echo "Starting Wireshark..."
if ! pgrep -f "wireshark" > /dev/null 2>&1; then
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

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== TTL OS Fingerprinting setup complete ==="