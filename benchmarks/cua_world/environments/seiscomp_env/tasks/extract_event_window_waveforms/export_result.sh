#!/bin/bash
echo "=== Exporting extract_event_window_waveforms result ==="

# 1. Take final screenshot
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Use a Python script to robustly extract file info, DB origin time, and miniSEED metadata
cat > /tmp/analyze_result.py << 'EOF'
import subprocess
import json
import sys
import os
from datetime import datetime

# Read task start time
try:
    with open("/tmp/task_start_time.txt", "r") as f:
        task_start = float(f.read().strip())
except Exception:
    task_start = 0.0

stats = {
    "file_exists": False,
    "file_size": 0,
    "min_start": 99999999999.0,
    "max_end": 0.0,
    "stations": [],
    "stream_count": 0,
    "ot_epoch": 0,
    "ot_string": "",
    "error": None,
    "task_start": task_start,
    "file_created_during_task": False
}

mseed_file = "/home/ga/noto_event_data.mseed"

# Query true origin time from MariaDB
try:
    ot_query = "SELECT time_value FROM Origin JOIN Event ON Event.preferredOriginID = Origin._oid LIMIT 1"
    ot_str = subprocess.check_output(["mysql", "-u", "sysop", "-psysop", "seiscomp", "-N", "-B", "-e", ot_query], text=True).strip()
    stats["ot_string"] = ot_str
    
    # Format: 2024-01-01 07:10:09.123456 or 2024-01-01 07:10:09
    fmt = "%Y-%m-%d %H:%M:%S.%f" if "." in ot_str else "%Y-%m-%d %H:%M:%S"
    stats["ot_epoch"] = datetime.strptime(ot_str, fmt).timestamp()
except Exception as e:
    stats["error"] = f"DB Query failed: {e}"

# Check output file and parse with scmssort
if os.path.exists(mseed_file):
    stats["file_exists"] = True
    stats["file_size"] = os.path.getsize(mseed_file)
    mtime = os.path.getmtime(mseed_file)
    if mtime >= task_start:
        stats["file_created_during_task"] = True

    try:
        # scmssort --list outputs format like: GE.BKB..BHZ 2024-01-01 07:09:09.000 ~ 2024-01-01 07:20:09.000
        out = subprocess.check_output(["/home/ga/seiscomp/bin/scmssort", "--list", mseed_file], text=True)
        stations = set()
        
        for line in out.strip().split('\n'):
            parts = line.split()
            if len(parts) >= 5:
                stream_id = parts[0]
                if '.' in stream_id:
                    sta = stream_id.split('.')[1]
                    stations.add(sta)
                
                start_str = parts[1] + " " + parts[2]
                end_str = parts[4] + " " + parts[5]
                
                if "." not in start_str: start_str += ".000"
                if "." not in end_str: end_str += ".000"
                
                fmt = "%Y-%m-%d %H:%M:%S.%f"
                start_ts = datetime.strptime(start_str, fmt).timestamp()
                end_ts = datetime.strptime(end_str, fmt).timestamp()
                
                stats["min_start"] = min(stats["min_start"], start_ts)
                stats["max_end"] = max(stats["max_end"], end_ts)
                stats["stream_count"] += 1
                
        stats["stations"] = list(stations)
    except Exception as e:
        if not stats["error"]:
            stats["error"] = f"scmssort failed: {e}"

# Reset placeholders if no streams were parsed
if stats["min_start"] == 99999999999.0:
    stats["min_start"] = 0.0

with open("/tmp/task_result.json", "w") as f:
    json.dump(stats, f)
EOF

# Run the analysis script
python3 /tmp/analyze_result.py

# Ensure permissions are open for the verifier
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="