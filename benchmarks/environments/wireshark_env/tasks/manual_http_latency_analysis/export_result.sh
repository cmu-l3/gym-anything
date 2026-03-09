#!/bin/bash
set -e
echo "=== Exporting Manual HTTP Latency Analysis Result ==="

PCAP_PATH="/home/ga/Documents/captures/http.cap"
REPORT_PATH="/home/ga/Documents/captures/latency_report.json"
EVIDENCE_PATH="/home/ga/Documents/captures/latency_evidence.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# --- 1. Calculate Ground Truth using tshark ---
# We calculate this dynamically to ensure it matches the exact file on disk.

# Network Latency: First SYN to First SYN-ACK
# Filter: tcp.flags.syn==1 && tcp.flags.ack==0 (SYN)
TS_SYN=$(tshark -r "$PCAP_PATH" -Y "tcp.flags.syn==1 && tcp.flags.ack==0" -T fields -e frame.time_epoch -c 1 2>/dev/null || echo "0")
# Filter: tcp.flags.syn==1 && tcp.flags.ack==1 (SYN-ACK)
TS_SYNACK=$(tshark -r "$PCAP_PATH" -Y "tcp.flags.syn==1 && tcp.flags.ack==1" -T fields -e frame.time_epoch -c 1 2>/dev/null || echo "0")

# Application Latency: HTTP GET to HTTP 200 OK
# Filter: http.request.method=="GET"
TS_GET=$(tshark -r "$PCAP_PATH" -Y "http.request.method==\"GET\"" -T fields -e frame.time_epoch -c 1 2>/dev/null || echo "0")
# Filter: http.response.code==200
TS_RESP=$(tshark -r "$PCAP_PATH" -Y "http.response.code==200" -T fields -e frame.time_epoch -c 1 2>/dev/null || echo "0")

# Python script to calculate deltas and package everything
python3 -c "
import json
import os
import sys

try:
    # timestamps from bash variables
    ts_syn = float('$TS_SYN')
    ts_synack = float('$TS_SYNACK')
    ts_get = float('$TS_GET')
    ts_resp = float('$TS_RESP')
    
    gt_network = ts_synack - ts_syn
    gt_server = ts_resp - ts_get
except ValueError:
    gt_network = -1.0
    gt_server = -1.0

# Check User Report
user_report = {}
report_exists = False
report_valid = False
report_created_in_task = False

report_path = '$REPORT_PATH'
if os.path.exists(report_path):
    report_exists = True
    mtime = os.path.getmtime(report_path)
    if mtime > float('$TASK_START'):
        report_created_in_task = True
    try:
        with open(report_path, 'r') as f:
            user_report = json.load(f)
            # Validate keys
            if 'network_latency_seconds' in user_report and 'server_processing_seconds' in user_report:
                report_valid = True
    except Exception as e:
        print(f'Error parsing report: {e}')

# Check Evidence Screenshot
evidence_exists = False
evidence_path = '$EVIDENCE_PATH'
if os.path.exists(evidence_path):
    evidence_exists = True

result = {
    'ground_truth': {
        'network_latency': gt_network,
        'server_latency': gt_server,
        'ts_syn': ts_syn,
        'ts_synack': ts_synack,
        'ts_get': ts_get,
        'ts_resp': ts_resp
    },
    'user_report': user_report,
    'checks': {
        'report_exists': report_exists,
        'report_valid': report_valid,
        'report_created_in_task': report_created_in_task,
        'evidence_exists': evidence_exists
    }
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)
"

# --- 2. Take Final Screenshot for VLM ---
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# --- 3. Permissions ---
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="