#!/bin/bash
echo "=== Exporting MFT Record Extraction Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import os, json, hashlib

result = {
    "task_start": 0,
    "task_end": 0,
    "report_exists": False,
    "report_mtime": 0,
    "parsed_report": {},
    "mft_record_exists": False,
    "mft_record_mtime": 0,
    "mft_record_size": 0,
    "mft_record_hash": "",
    "file_content_exists": False,
    "file_content_mtime": 0,
    "file_content_hash": "",
    "error": ""
}

try:
    with open('/tmp/task_start_time.txt') as f:
        result['task_start'] = int(f.read().strip())
except: pass

# 1. Parse Report
report_path = "/home/ga/Reports/daubert_validation.txt"
if os.path.exists(report_path):
    result["report_exists"] = True
    result["report_mtime"] = int(os.path.getmtime(report_path))
    
    parsed = {}
    with open(report_path, 'r', errors='ignore') as f:
        for line in f:
            if ':' in line:
                k, v = line.split(':', 1)
                parsed[k.strip().upper()] = v.strip()
    result["parsed_report"] = parsed

# 2. Check MFT Record
mft_path = "/home/ga/Reports/target_mft_record.bin"
if os.path.exists(mft_path):
    result["mft_record_exists"] = True
    result["mft_record_mtime"] = int(os.path.getmtime(mft_path))
    result["mft_record_size"] = os.path.getsize(mft_path)
    
    with open(mft_path, 'rb') as f:
        data = f.read()
        result["mft_record_hash"] = hashlib.sha256(data).hexdigest()

# 3. Check File Content
content_path = "/home/ga/Reports/target_file_content.bin"
if os.path.exists(content_path):
    result["file_content_exists"] = True
    result["file_content_mtime"] = int(os.path.getmtime(content_path))
    
    with open(content_path, 'rb') as f:
        data = f.read()
        result["file_content_hash"] = hashlib.sha256(data).hexdigest()

with open("/tmp/mft_result.json", "w") as f:
    json.dump(result, f, indent=2)
    
print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/mft_result.json

echo "=== Export complete ==="