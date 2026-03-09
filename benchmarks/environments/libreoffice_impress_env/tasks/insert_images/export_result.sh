#!/bin/bash
echo "=== Exporting insert_images result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Capture final state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

PRES_DIR="/home/ga/Documents/Presentations"
ODP_FILE="$PRES_DIR/sustainability_report.odp"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check if app is running
APP_RUNNING=$(pgrep -f "soffice.bin" > /dev/null && echo "true" || echo "false")

# Run analysis script inside container
# This avoids needing complex dependencies on the host verifier
python3 << PYEOF
import json
import os
import sys
import time

try:
    sys.path.insert(0, '/workspace/utils')
    from impress_verification_utils import parse_odp_file, check_slide_has_images
    
    filepath = "$ODP_FILE"
    result = {
        "file_exists": False,
        "file_modified_during_task": False,
        "slide_count": 0,
        "slides_with_images": {},
        "app_running": "$APP_RUNNING" == "true"
    }

    if os.path.exists(filepath):
        result["file_exists"] = True
        
        # Check timestamp
        mtime = os.path.getmtime(filepath)
        start_time = float($TASK_START)
        if mtime > start_time:
            result["file_modified_during_task"] = True
            
        # Parse ODP
        try:
            data = parse_odp_file(filepath)
            if 'error' not in data:
                result["slide_count"] = data.get('slide_count', 0)
                
                # Check images per slide
                for i in range(result["slide_count"]):
                    has_img = check_slide_has_images(data, i)
                    result["slides_with_images"][str(i)] = has_img # Use string keys for JSON
            else:
                result["error"] = data.get('error')
        except Exception as e:
            result["error"] = str(e)
            
    # Write result
    with open('/tmp/analysis_result.json', 'w') as f:
        json.dump(result, f)

except Exception as e:
    with open('/tmp/analysis_result.json', 'w') as f:
        json.dump({"error": str(e), "critical_failure": True}, f)
PYEOF

# Move result to safe location with loose permissions
cp /tmp/analysis_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json