#!/bin/bash
echo "=== Exporting results for tsk_fragmentation_profiling ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import json, os, hashlib

result = {
    "task": "tsk_fragmentation_profiling",
    "csv_exists": False,
    "csv_mtime": 0,
    "csv_content": "",
    "txt_exists": False,
    "txt_mtime": 0,
    "txt_content": "",
    "bin_exists": False,
    "bin_mtime": 0,
    "bin_size": 0,
    "bin_hash": "",
    "start_time": 0,
    "error": ""
}

# 1. Start time
try:
    with open("/tmp/tsk_fragmentation_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# 2. CSV File
csv_path = "/home/ga/Reports/fragment_counts.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_mtime"] = int(os.path.getmtime(csv_path))
    try:
        with open(csv_path, "r", errors="replace") as f:
            result["csv_content"] = f.read(100000) # Read up to 100KB safely
    except Exception as e:
        result["error"] += f" | CSV read error: {e}"

# 3. TXT File
txt_path = "/home/ga/Reports/most_fragmented_analysis.txt"
if os.path.exists(txt_path):
    result["txt_exists"] = True
    result["txt_mtime"] = int(os.path.getmtime(txt_path))
    try:
        with open(txt_path, "r", errors="replace") as f:
            result["txt_content"] = f.read(2048)
    except Exception as e:
        result["error"] += f" | TXT read error: {e}"

# 4. BIN File
bin_path = "/home/ga/Reports/fragment_start.bin"
if os.path.exists(bin_path):
    result["bin_exists"] = True
    result["bin_mtime"] = int(os.path.getmtime(bin_path))
    result["bin_size"] = os.path.getsize(bin_path)
    try:
        with open(bin_path, "rb") as f:
            data = f.read()
            result["bin_hash"] = hashlib.sha256(data).hexdigest()
    except Exception as e:
        result["error"] += f" | BIN read error: {e}"

print(json.dumps(result, indent=2))
with open("/tmp/fragmentation_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/fragmentation_result.json")
PYEOF

echo "=== Export complete ==="