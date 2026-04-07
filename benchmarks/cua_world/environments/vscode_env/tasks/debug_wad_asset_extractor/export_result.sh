#!/bin/bash
echo "=== Exporting Debug WAD Asset Extractor Result ==="

WORKSPACE_DIR="/home/ga/workspace/wad_extractor"
RESULT_FILE="/tmp/wad_extractor_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Try to force VSCode to save open files
DISPLAY=:1 xdotool key --delay 100 ctrl+shift+s 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key --delay 100 ctrl+k ctrl+s 2>/dev/null || true
sleep 1

# Collect all relevant source files into a single JSON
python3 << PYEXPORT
import json, os

workspace = "$WORKSPACE_DIR"
files_to_export = [
    "wad_parser.py",
    "extractor.py",
    "playpal_converter.py",
    "main.py"
]

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "files": {}
}

for rel_path in files_to_export:
    path = os.path.join(workspace, rel_path)
    try:
        with open(path, "r", encoding="utf-8") as f:
            result["files"][rel_path] = f.read()
    except Exception as e:
        result["files"][rel_path] = f"ERROR: {e}"

# Also check if the agent successfully produced an output directory
out_dir = os.path.join(workspace, "output")
result["output_dir_exists"] = os.path.isdir(out_dir)
if os.path.isdir(out_dir):
    result["extracted_file_count"] = len(os.listdir(out_dir))
    
    # Check if PLAYPAL_0.txt exists
    pp_path = os.path.join(out_dir, "PLAYPAL_0.txt")
    result["playpal_exists"] = os.path.isfile(pp_path)
    if os.path.isfile(pp_path):
        with open(pp_path, "r") as f:
            result["playpal_head"] = "".join(f.readlines()[:5])
else:
    result["extracted_file_count"] = 0
    result["playpal_exists"] = False

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)

print(f"Exported data to $RESULT_FILE")
PYEXPORT

chmod 666 "$RESULT_FILE" 2>/dev/null || true
echo "=== Export Complete ==="