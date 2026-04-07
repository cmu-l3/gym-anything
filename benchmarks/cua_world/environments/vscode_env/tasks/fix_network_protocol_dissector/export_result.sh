#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Exporting Network Protocol Dissector Result ==="

WORKSPACE_DIR="/home/ga/workspace/packet_dissector"
RESULT_FILE="/tmp/packet_dissector_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Force VSCode to save all files
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# Remove old result file
rm -f "$RESULT_FILE"

# Collect file content and modified timestamps
python3 << PYEXPORT
import json, os, stat

workspace = "$WORKSPACE_DIR"
task_start = int("$TASK_START")

files_to_export = [
    "parsers/ip_parser.py",
    "parsers/tcp_tracker.py",
    "parsers/dns_parser.py",
    "parsers/http_parser.py",
    "parsers/tls_parser.py"
]

result = {
    "task_start": task_start,
    "task_end": int("$TASK_END"),
    "files": {}
}

for rel_path in files_to_export:
    full_path = os.path.join(workspace, rel_path)
    file_data = {
        "content": None,
        "mtime": 0,
        "modified_during_task": False
    }
    
    try:
        if os.path.exists(full_path):
            with open(full_path, "r", encoding="utf-8") as f:
                file_data["content"] = f.read()
            mtime = int(os.stat(full_path).st_mtime)
            file_data["mtime"] = mtime
            file_data["modified_during_task"] = mtime >= task_start
        else:
            file_data["content"] = f"ERROR: File not found"
    except Exception as e:
        file_data["content"] = f"ERROR: {e}"
        
    result["files"][rel_path] = file_data

# Save output
with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)

print(f"Exported files to $RESULT_FILE")
PYEXPORT

# Fix permissions
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "=== Export Complete ==="