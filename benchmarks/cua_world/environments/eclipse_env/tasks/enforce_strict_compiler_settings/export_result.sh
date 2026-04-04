#!/bin/bash
echo "=== Exporting enforce_strict_compiler_settings result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

PROJECT_DIR="/home/ga/eclipse-workspace/RadiationPlanningCore"
PREFS_FILE="$PROJECT_DIR/.settings/org.eclipse.jdt.core.prefs"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Check if prefs file exists and was modified
PREFS_EXISTS="false"
PREFS_MODIFIED="false"
PREFS_MTIME=0

if [ -f "$PREFS_FILE" ]; then
    PREFS_EXISTS="true"
    PREFS_MTIME=$(stat -c %Y "$PREFS_FILE" 2>/dev/null || echo "0")
    
    if [ "$PREFS_MTIME" -gt "$TASK_START" ]; then
        PREFS_MODIFIED="true"
    fi
fi

# Prepare content for export (handled safely by python to avoid JSON escaping issues)
PREFS_CONTENT=""
if [ -f "$PREFS_FILE" ]; then
    PREFS_CONTENT=$(cat "$PREFS_FILE")
fi

# Create JSON result using Python to safely handle strings
python3 -c "
import json
import os
import time

try:
    content = '''$PREFS_CONTENT'''
    result = {
        'task_start': $TASK_START,
        'task_end': $TASK_END,
        'prefs_exists': $PREFS_EXISTS,
        'prefs_modified': $PREFS_MODIFIED,
        'prefs_path': '$PREFS_FILE',
        'screenshot_path': '/tmp/task_end.png'
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
except Exception as e:
    print(f'Error creating JSON: {e}')
"

# Set permissions so verifier can read it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="