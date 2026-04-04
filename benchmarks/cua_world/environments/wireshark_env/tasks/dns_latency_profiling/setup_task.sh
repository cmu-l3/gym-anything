#!/bin/bash
set -e

echo "=== Setting up DNS Latency Profiling task ==="

# 1. Clean up previous artifacts
rm -f /home/ga/Documents/captures/dns_latency_report.txt
rm -f /tmp/dns_ground_truth.json
rm -f /tmp/task_start_time.txt
rm -f /tmp/task_initial.png

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Verify PCAP file exists
PCAP_FILE="/home/ga/Documents/captures/dns.cap"
if [ ! -f "$PCAP_FILE" ]; then
    echo "ERROR: PCAP file not found at $PCAP_FILE"
    exit 1
fi

# 4. Generate Ground Truth using Python + Tshark
# We do this in setup to ensure we have the 'correct' answer before the agent starts
# and to avoid dependencies on agent's actions.

echo "Calculating ground truth..."
python3 -c "
import subprocess
import json
import statistics
import sys

pcap_file = '$PCAP_FILE'

def get_tshark_output(args):
    cmd = ['tshark', '-r', pcap_file] + args
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.stdout.strip().splitlines()

# 1. Count Total Queries (dns.flags.response == 0)
queries = get_tshark_output(['-Y', 'dns.flags.response == 0'])
total_queries = len(queries)

# 2. Extract Response Times and Domains
# dns.time is the response time calculated by Wireshark (delta between query and response)
# It is present in Response packets (dns.flags.response == 1)
data_lines = get_tshark_output([
    '-Y', 'dns.flags.response == 1 && dns.time',
    '-T', 'fields',
    '-e', 'dns.qry.name',
    '-e', 'dns.time'
])

latencies = []
domain_latency_map = []

for line in data_lines:
    parts = line.split('\t')
    if len(parts) >= 2:
        domain = parts[0]
        try:
            # dns.time is in seconds, task asks for ms
            time_sec = float(parts[1])
            time_ms = time_sec * 1000.0
            latencies.append(time_ms)
            domain_latency_map.append((domain, time_ms))
        except ValueError:
            continue

answered_queries = len(latencies)
unanswered_queries = total_queries - answered_queries

stats = {
    'min': 0, 'max': 0, 'mean': 0, 'median': 0,
    'slowest_domain': '', 'slowest_latency': 0
}

if latencies:
    stats['min'] = min(latencies)
    stats['max'] = max(latencies)
    stats['mean'] = statistics.mean(latencies)
    stats['median'] = statistics.median(latencies)
    
    # Find slowest domain
    # Sort by latency desc
    domain_latency_map.sort(key=lambda x: x[1], reverse=True)
    stats['slowest_domain'] = domain_latency_map[0][0]
    stats['slowest_latency'] = domain_latency_map[0][1]

ground_truth = {
    'total_queries': total_queries,
    'answered_queries': answered_queries,
    'unanswered_queries': unanswered_queries,
    'stats': stats
}

with open('/tmp/dns_ground_truth.json', 'w') as f:
    json.dump(ground_truth, f, indent=4)

print(json.dumps(ground_truth, indent=2))
"

# 5. Launch Wireshark
echo "Launching Wireshark..."
su - ga -c "DISPLAY=:1 wireshark '$PCAP_FILE' &"

# 6. Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Wireshark"; then
        echo "Wireshark window found"
        sleep 1
        DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz
        break
    fi
    sleep 1
done

# 7. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="