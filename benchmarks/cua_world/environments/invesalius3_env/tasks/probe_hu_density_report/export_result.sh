#!/bin/bash
set -e
echo "=== Exporting probe_hu_density_report result ==="

source /workspace/scripts/task_utils.sh

# Configuration
OUTPUT_FILE="/home/ga/Documents/hu_density_report.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT_JSON="/tmp/task_result.json"

# 1. Capture Final State Evidence
take_screenshot /tmp/task_final.png

# 2. Analyze Output File
# Use Python to robustly parse the text file and check file metadata
python3 << PYEOF
import os
import json
import re
import time

output_path = "$OUTPUT_FILE"
task_start = $TASK_START
result = {
    "file_exists": False,
    "file_created_during_task": False,
    "content_valid": False,
    "parsed_values": {},
    "timestamp": time.time()
}

if os.path.exists(output_path):
    result["file_exists"] = True
    
    # Check timestamp
    mtime = os.path.getmtime(output_path)
    if mtime > task_start:
        result["file_created_during_task"] = True
        
    # Parse content
    try:
        with open(output_path, 'r') as f:
            content = f.read()
            
        # Regex to find 'label: value' patterns, case-insensitive
        # Matches: "cortical_bone: 123", "Cortical Bone : -50.5", etc.
        patterns = {
            "cortical_bone": r"(?i)cortical[_ ]?bone\s*:\s*([-+]?\d*\.?\d+)",
            "air": r"(?i)air\s*:\s*([-+]?\d*\.?\d+)",
            "soft_tissue": r"(?i)soft[_ ]?tissue\s*:\s*([-+]?\d*\.?\d+)"
        }
        
        parsed = {}
        for key, pattern in patterns.items():
            match = re.search(pattern, content)
            if match:
                try:
                    parsed[key] = float(match.group(1))
                except ValueError:
                    pass
        
        result["parsed_values"] = parsed
        
        # specific check: did we find all three keys?
        if len(parsed) == 3:
            result["content_valid"] = True
            
    except Exception as e:
        result["error"] = str(e)

# Save result to JSON
with open("$EXPORT_JSON", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# 3. Permissions
chmod 666 "$EXPORT_JSON" 2>/dev/null || true

echo "=== Export Complete ==="