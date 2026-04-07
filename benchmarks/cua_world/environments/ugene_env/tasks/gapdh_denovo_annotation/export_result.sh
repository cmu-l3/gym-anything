#!/bin/bash
echo "=== Exporting GAPDH Annotation Results ==="

# Record task end
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if UGENE is still running
UGENE_RUNNING="false"
if pgrep -f "ugene" > /dev/null; then
    UGENE_RUNNING="true"
fi

# We use Python to carefully read files and encode them into a JSON to avoid bash quoting nightmares
cat > /tmp/export_parser.py << 'EOF'
import json
import os
import sys

RESULTS_DIR = "/home/ga/UGENE_Data/gapdh/results"
GB_FILE = os.path.join(RESULTS_DIR, "gapdh_annotated.gb")
PROT_FILE = os.path.join(RESULTS_DIR, "gapdh_protein.fa")
REPORT_FILE = os.path.join(RESULTS_DIR, "annotation_report.txt")

task_start = int(sys.argv[1]) if len(sys.argv) > 1 else 0

def get_file_info(filepath):
    exists = os.path.exists(filepath)
    if not exists:
        return {"exists": False, "created_during_task": False, "size": 0, "content": ""}
    
    mtime = os.path.getmtime(filepath)
    size = os.path.getsize(filepath)
    created_during_task = mtime >= task_start if task_start > 0 else True
    
    content = ""
    # Only read if size is reasonable (e.g. < 1MB)
    if size < 1024 * 1024:
        try:
            with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
                content = f.read()
        except Exception:
            pass
            
    return {
        "exists": exists,
        "created_during_task": created_during_task,
        "size": size,
        "content": content
    }

data = {
    "ugene_running": sys.argv[2] == "true",
    "genbank": get_file_info(GB_FILE),
    "protein": get_file_info(PROT_FILE),
    "report": get_file_info(REPORT_FILE)
}

with open("/tmp/task_result.json", "w", encoding='utf-8') as f:
    json.dump(data, f, indent=2)
EOF

python3 /tmp/export_parser.py "$TASK_START" "$UGENE_RUNNING"

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result packaged to /tmp/task_result.json"
echo "=== Export complete ==="