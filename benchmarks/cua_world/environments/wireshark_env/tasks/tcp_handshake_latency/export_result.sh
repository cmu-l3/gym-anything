#!/bin/bash
set -e

echo "=== Exporting TCP Handshake Latency Results ==="

# Paths
PCAP_PATH="/home/ga/Documents/captures/200722_tcp_anon.pcapng"
USER_CSV="/home/ga/Documents/captures/handshake_latencies.csv"
USER_SUMMARY="/home/ga/Documents/captures/handshake_summary.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# ---------------------------------------------------------
# GENERATE GROUND TRUTH (Internal Calculation)
# ---------------------------------------------------------
# We use python inside the container to reliably calculate stats from tshark output
# This avoids depending on host tools and handles the logic in one place.

# Extract raw data using tshark
# Fields: src, dst, srcport, dstport, initial_rtt
# We filter for packets that HAVE an initial_rtt calculated
echo "Extracting ground truth data..."
tshark -r "$PCAP_PATH" \
    -Y "tcp.analysis.initial_rtt" \
    -T fields \
    -e ip.src -e ip.dst -e tcp.srcport -e tcp.dstport -e tcp.analysis.initial_rtt \
    -E separator=, -E header=n -E quote=d \
    > /tmp/ground_truth_raw.csv 2>/dev/null

# ---------------------------------------------------------
# COMPARISON SCRIPT (Python)
# ---------------------------------------------------------
# This script compares User CSV vs Ground Truth and parses User Summary
cat << 'EOF' > /tmp/compare_results.py
import csv
import json
import sys
import os
import math

def parse_csv(filepath):
    data = {} # Key: "src:sport->dst:dport", Value: rtt (float)
    try:
        with open(filepath, 'r') as f:
            reader = csv.reader(f)
            header = next(reader, None)
            if not header: return None
            
            # Simple column index mapping (flexible case)
            cols = {h.lower().strip(): i for i, h in enumerate(header)}
            
            # Check required columns
            req = ['src_ip', 'dst_ip', 'src_port', 'dst_port', 'initial_rtt_seconds']
            if not all(r in cols for r in req):
                return {'error': f"Missing columns. Found: {list(cols.keys())}"}

            for row in reader:
                if len(row) < 5: continue
                try:
                    s_ip = row[cols['src_ip']].strip()
                    d_ip = row[cols['dst_ip']].strip()
                    s_port = row[cols['src_port']].strip()
                    d_port = row[cols['dst_port']].strip()
                    rtt = float(row[cols['initial_rtt_seconds']].strip())
                    
                    # Create a unique key for the connection
                    key = f"{s_ip}:{s_port}->{d_ip}:{d_port}"
                    data[key] = rtt
                except ValueError:
                    continue
    except Exception as e:
        return {'error': str(e)}
    return data

def parse_ground_truth(filepath):
    data = {}
    try:
        with open(filepath, 'r') as f:
            # tshark output: "src","dst","sport","dport","rtt"
            reader = csv.reader(f)
            for row in reader:
                if len(row) < 5: continue
                s_ip, d_ip, s_port, d_port, rtt_str = row
                try:
                    rtt = float(rtt_str)
                    key = f"{s_ip}:{s_port}->{d_ip}:{d_port}"
                    # If multiple handshake packets (retransmissions), keep first or avg? 
                    # Wireshark usually calculates it once per flow. We'll overwrite.
                    data[key] = rtt
                except ValueError:
                    continue
    except Exception as e:
        return {}
    return data

def parse_summary(filepath):
    content = ""
    try:
        with open(filepath, 'r') as f:
            content = f.read().lower()
    except:
        return {}
    
    # Heuristic extraction
    import re
    stats = {}
    
    # Extract numbers for count, min, max, mean
    # Look for patterns like "Total: 15" or "Min: 0.123"
    patterns = {
        'count': [r'total.*?(\d+)', r'count.*?(\d+)'],
        'min': [r'min.*?(\d+\.?\d*)'],
        'max': [r'max.*?(\d+\.?\d*)'],
        'mean': [r'mean.*?(\d+\.?\d*)', r'avg.*?(\d+\.?\d*)', r'average.*?(\d+\.?\d*)']
    }
    
    for key, regexes in patterns.items():
        for reg in regexes:
            m = re.search(reg, content)
            if m:
                try:
                    stats[key] = float(m.group(1))
                    break
                except: pass
                
    stats['content_preview'] = content[:200]
    return stats

# --- Main Logic ---
user_csv_path = sys.argv[1]
user_summary_path = sys.argv[2]
gt_raw_path = sys.argv[3]

results = {
    'csv_exists': os.path.exists(user_csv_path),
    'summary_exists': os.path.exists(user_summary_path),
    'csv_valid': False,
    'csv_error': None,
    'connection_count_match': False,
    'matches_count': 0,
    'matches_total': 0,
    'stats_accuracy': {},
    'slowest_connection_correct': False
}

# 1. Analyze Ground Truth
gt_data = parse_ground_truth(gt_raw_path)
results['ground_truth_count'] = len(gt_data)

if not gt_data:
    print(json.dumps(results))
    sys.exit(0)

gt_rtts = list(gt_data.values())
gt_stats = {
    'min_ms': min(gt_rtts) * 1000,
    'max_ms': max(gt_rtts) * 1000,
    'mean_ms': (sum(gt_rtts) / len(gt_rtts)) * 1000
}

# Identify slowest connection in GT
slowest_key = max(gt_data, key=gt_data.get)
slowest_parts = slowest_key.split('->')[1].split(':') # dst_ip:dst_port
gt_slowest_target = f"{slowest_parts[0]}:{slowest_parts[1]}" # ip:port

# 2. Analyze User CSV
if results['csv_exists']:
    user_data = parse_csv(user_csv_path)
    if isinstance(user_data, dict) and 'error' not in user_data:
        results['csv_valid'] = True
        results['user_count'] = len(user_data)
        
        # Check Count
        if len(user_data) == len(gt_data):
            results['connection_count_match'] = True
            
        # Check Values (1% tolerance)
        matches = 0
        for k, u_rtt in user_data.items():
            if k in gt_data:
                g_rtt = gt_data[k]
                if math.isclose(u_rtt, g_rtt, rel_tol=0.01):
                    matches += 1
        results['matches_count'] = matches
        results['matches_total'] = len(gt_data)
    elif isinstance(user_data, dict):
        results['csv_error'] = user_data.get('error')

# 3. Analyze User Summary
if results['summary_exists']:
    user_stats = parse_summary(user_summary_path)
    results['user_stats_extracted'] = user_stats
    
    acc = {}
    # Check Min
    if 'min' in user_stats:
        acc['min_ok'] = math.isclose(user_stats['min'], gt_stats['min_ms'], rel_tol=0.01)
    # Check Max
    if 'max' in user_stats:
        acc['max_ok'] = math.isclose(user_stats['max'], gt_stats['max_ms'], rel_tol=0.01)
    # Check Mean (5% tolerance)
    if 'mean' in user_stats:
        acc['mean_ok'] = math.isclose(user_stats['mean'], gt_stats['mean_ms'], rel_tol=0.05)
        
    results['stats_accuracy'] = acc
    
    # Check Slowest Connection content
    # We look for the destination IP and Port of the slowest connection in the text
    content = user_stats.get('content_preview', '')
    slowest_ip, slowest_port = gt_slowest_target.split(':')
    if slowest_ip in content and slowest_port in content:
        results['slowest_connection_correct'] = True

print(json.dumps(results))
EOF

# Execute comparison
echo "Comparing results..."
python3 /tmp/compare_results.py "$USER_CSV" "$USER_SUMMARY" "/tmp/ground_truth_raw.csv" > /tmp/comparison_output.json

# ---------------------------------------------------------
# FINALIZE JSON
# ---------------------------------------------------------
# Check timestamps for anti-gaming
CSV_NEW="false"
SUM_NEW="false"

if [ -f "$USER_CSV" ]; then
    F_TIME=$(stat -c %Y "$USER_CSV")
    if [ "$F_TIME" -gt "$TASK_START" ]; then CSV_NEW="true"; fi
fi

if [ -f "$USER_SUMMARY" ]; then
    F_TIME=$(stat -c %Y "$USER_SUMMARY")
    if [ "$F_TIME" -gt "$TASK_START" ]; then SUM_NEW="true"; fi
fi

# Merge comparison output with file stats
jq -n \
    --slurpfile comp /tmp/comparison_output.json \
    --arg csv_new "$CSV_NEW" \
    --arg sum_new "$SUM_NEW" \
    --arg task_start "$TASK_START" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        comparison: $comp[0],
        files_created_during_task: {
            csv: $csv_new,
            summary: $sum_new
        },
        meta: {
            timestamp: $timestamp,
            task_start_epoch: $task_start
        }
    }' > /tmp/task_result.json

# Cleanup and Permissions
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="
cat /tmp/task_result.json