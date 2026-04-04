#!/bin/bash
set -e
echo "=== Exporting capinfos_forensic_profiling result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Python script to gather all data (User report + Ground Truth)
# We do this in Python inside the container to handle JSON parsing reliably
# and to run subprocesses for capinfos/tshark verification.

cat << 'EOF' > /tmp/gather_results.py
import json
import os
import subprocess
import sys
import glob

# Configuration
REPORT_PATH = "/home/ga/Documents/forensic_report.json"
CAPTURES_DIR = "/home/ga/Documents/captures"
REQUIRED_FILES = ["http.cap", "dns.cap", "telnet-cooked.pcap", "200722_tcp_anon.pcapng", "smtp.pcap"]
TASK_START = int(sys.argv[1])
TASK_END = int(sys.argv[2])

result_data = {
    "meta": {
        "task_start": TASK_START,
        "task_end": TASK_END,
        "report_exists": False,
        "report_valid_json": False,
        "file_created_during_task": False,
        "file_size": 0
    },
    "user_report": {},
    "ground_truth": {}
}

# 1. Check User Report
if os.path.exists(REPORT_PATH):
    result_data["meta"]["report_exists"] = True
    stat = os.stat(REPORT_PATH)
    result_data["meta"]["file_size"] = stat.st_size
    
    # Check timestamp
    if stat.st_mtime > TASK_START:
        result_data["meta"]["file_created_during_task"] = True
        
    # Parse JSON
    try:
        with open(REPORT_PATH, 'r') as f:
            user_json = json.load(f)
            result_data["user_report"] = user_json
            result_data["meta"]["report_valid_json"] = True
    except Exception as e:
        result_data["meta"]["json_error"] = str(e)

# 2. Compute Ground Truth
gt_data = {"files": {}, "summary": {}}
total_packets = 0
most_packets = {"file": "", "count": -1}
longest_duration = {"file": "", "duration": -1.0}
largest_avg_size = {"file": "", "size": -1.0}

for fname in REQUIRED_FILES:
    fpath = os.path.join(CAPTURES_DIR, fname)
    if not os.path.exists(fpath):
        continue
        
    file_info = {"filename": fname}
    
    # File size
    file_info["file_size_bytes"] = os.path.getsize(fpath)
    
    # Run capinfos for most data
    # -c: packet count, -u: duration, -E: encapsulation, -k: capture duration (alt)
    # We use tshark for packet count usually as it's definitive, but capinfos is faster.
    # Let's use tshark for count to be precise, capinfos for others.
    
    try:
        # Packet count (tshark is reliable)
        p = subprocess.run(["tshark", "-r", fpath], capture_output=True, text=True)
        # Count lines, excluding empty ones
        packet_count = len([x for x in p.stdout.split('\n') if x.strip()])
        file_info["packet_count"] = packet_count
        total_packets += packet_count
        
        if packet_count > most_packets["count"]:
            most_packets["count"] = packet_count
            most_packets["file"] = fname
            
    except Exception as e:
        file_info["error_count"] = str(e)

    try:
        # Duration and Avg Size via capinfos
        # capinfos -T (table) -r (header) -m (separate by comma? no, -T returns tab by default)
        # Easier to parse specific flags:
        # -u: duration seconds
        # -l: average packet size (not directly available as simple flag output in some versions, parsing text is safer)
        # -E: encapsulation
        
        proc = subprocess.run(["capinfos", "-T", "-r", "-u", "-d", "-E", fpath], capture_output=True, text=True)
        # Output format with -T -r:
        # File name	Capture duration	Average packet size	File encapsulation
        # But order depends on flags. Let's parse standard output for safety.
        
        proc_std = subprocess.run(["capinfos", fpath], capture_output=True, text=True)
        output = proc_std.stdout
        
        # Duration
        for line in output.split('\n'):
            if "Capture duration:" in line:
                # Example: "Capture duration:    2.340000 seconds"
                parts = line.split(":")
                val_str = parts[1].strip().split()[0] # get number
                try:
                    dur = float(val_str)
                    file_info["capture_duration_seconds"] = dur
                    if dur > longest_duration["duration"]:
                        longest_duration["duration"] = dur
                        longest_duration["file"] = fname
                except: pass
            
            if "Average packet size:" in line:
                # Example: "Average packet size: 345.67 bytes"
                parts = line.split(":")
                val_str = parts[1].strip().split()[0]
                try:
                    avg = float(val_str)
                    file_info["average_packet_size_bytes"] = avg
                    if avg > largest_avg_size["size"]:
                        largest_avg_size["size"] = avg
                        largest_avg_size["file"] = fname
                except: pass
                
            if "File encapsulation:" in line:
                # Example: "File encapsulation:  Ethernet"
                parts = line.split(":")
                encap = parts[1].strip()
                file_info["encapsulation"] = encap

    except Exception as e:
        file_info["error_capinfos"] = str(e)
        
    gt_data["files"][fname] = file_info

# Compute summary
gt_data["summary"] = {
    "total_packets_all_files": total_packets,
    "file_with_most_packets": most_packets["file"],
    "file_with_longest_duration": longest_duration["file"],
    "file_with_largest_avg_packet_size": largest_avg_size["file"]
}

result_data["ground_truth"] = gt_data

# Dump final JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result_data, f, indent=2)

EOF

# Execute the python script
python3 /tmp/gather_results.py "$TASK_START" "$TASK_END"

# Move result to final location with proper permissions
rm -f /tmp/final_result.json 2>/dev/null || true
cp /tmp/task_result.json /tmp/final_result.json
chmod 666 /tmp/final_result.json

echo "Result gathered at /tmp/final_result.json"
echo "=== Export complete ==="