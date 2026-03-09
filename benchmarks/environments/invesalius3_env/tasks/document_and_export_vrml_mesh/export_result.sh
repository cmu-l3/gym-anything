#!/bin/bash
# Export result for document_and_export_vrml_mesh task

echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

# Configuration
VRML_FILE="/home/ga/Documents/legacy_skull.wrl"
INFO_FILE="/home/ga/Documents/mesh_info.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_JSON="/tmp/task_result.json"

# Capture final state
take_screenshot /tmp/task_end.png

# Use Python to analyze the outputs (robust parsing)
python3 << PYEOF
import os
import json
import re
import sys

result = {
    "vrml_exists": False,
    "vrml_size_bytes": 0,
    "vrml_valid_header": False,
    "vrml_vertex_count": 0,
    "info_exists": False,
    "info_reported_count": 0,
    "files_created_during_task": False,
    "timestamp": 0
}

task_start = int("$TASK_START")
vrml_path = "$VRML_FILE"
info_path = "$INFO_FILE"

# 1. Analyze VRML File
if os.path.isfile(vrml_path):
    result["vrml_exists"] = True
    stat = os.stat(vrml_path)
    result["vrml_size_bytes"] = stat.st_size
    
    # Check timestamp
    if stat.st_mtime > task_start:
        result["files_created_during_task"] = True

    try:
        with open(vrml_path, 'r', encoding='utf-8', errors='ignore') as f:
            header = f.read(100)
            if "#VRML V2.0" in header:
                result["vrml_valid_header"] = True
            
            # VRML 2.0 Coordinate point counting
            # Structure: point [ x y z, x y z, ... ]
            # We will scan for the 'point [' block and count items
            f.seek(0)
            content = f.read()
            
            # Find the coordinate block
            # This is a heuristic: counting commas in the first large 'point [...]' block 
            # or counting lines if formatted one per line.
            # Robust method: find 'point [' then count sets of 3 floats until ']'
            
            # Regex to find the point block content
            match = re.search(r'point\s*\[(.*?)\]', content, re.DOTALL)
            if match:
                points_str = match.group(1)
                # Remove whitespace and split by commas or whitespace
                # VRML separates numbers by space or comma
                # This counts total numbers / 3
                tokens = points_str.replace(',', ' ').split()
                result["vrml_vertex_count"] = len(tokens) // 3
                
    except Exception as e:
        result["error_vrml"] = str(e)

# 2. Analyze Info File
if os.path.isfile(info_path):
    result["info_exists"] = True
    try:
        with open(info_path, 'r') as f:
            text = f.read().strip()
            # Extract first integer found
            numbers = re.findall(r'\d+', text)
            if numbers:
                result["info_reported_count"] = int(numbers[0])
    except Exception as e:
        result["error_info"] = str(e)

# Write result
with open("$RESULT_JSON", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Ensure permissions for copy_from_env
chmod 666 "$RESULT_JSON"

echo "=== Export Complete ==="