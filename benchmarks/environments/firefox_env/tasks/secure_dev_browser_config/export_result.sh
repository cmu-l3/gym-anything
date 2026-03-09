#!/bin/bash
# export_result.sh - Post-task hook for secure_dev_browser_config
set -e

echo "=== Exporting secure_dev_browser_config results ==="

# 1. Take final screenshot (before killing Firefox)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gracefully terminate Firefox to flush prefs.js to disk
# This is critical because Firefox writes runtime changes to prefs.js on shutdown
echo "Terminating Firefox to flush preferences..."
pkill -u ga -f firefox 2>/dev/null || true

# Wait for process to exit
for i in {1..20}; do
    if ! pgrep -u ga -f firefox > /dev/null; then
        echo "Firefox terminated."
        break
    fi
    sleep 1
done
# Force kill if still running
pkill -9 -u ga -f firefox 2>/dev/null || true

# 3. Locate profile and prefs.js
PROFILE_DIR=$(cat /tmp/firefox_profile_path 2>/dev/null || echo "")
if [ -z "$PROFILE_DIR" ] || [ ! -f "$PROFILE_DIR/prefs.js" ]; then
    # Try to find it again if setup script failed to save it
    PROFILE_DIR=$(find /home/ga -name "prefs.js" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null || echo "")
fi

PREFS_FILE="$PROFILE_DIR/prefs.js"
echo "Reading preferences from: $PREFS_FILE"

# 4. Check report file details
REPORT_FILE="/home/ga/Documents/browser_security_config.json"
REPORT_EXISTS="false"
REPORT_MTIME=0
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE")
fi

# 5. Extract preferences and create result JSON using Python
# We use Python to parse the prefs.js file reliably and the report JSON
python3 << EOF
import json
import os
import re
import sys

# Paths
prefs_file = "$PREFS_FILE"
report_file = "$REPORT_FILE"
output_json = "/tmp/task_result.json"

# Data to export
result = {
    "task_start_time": $TASK_START,
    "report_exists": $REPORT_EXISTS,
    "report_mtime": $REPORT_MTIME,
    "report_content": None,
    "actual_prefs": {},
    "profile_found": False
}

# 1. Parse prefs.js
# Format: user_pref("pref.name", value);
if os.path.exists(prefs_file):
    result["profile_found"] = True
    try:
        with open(prefs_file, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            
        # Regex to capture preference name and value
        # Values can be strings "str", ints 123, or booleans true/false
        pattern = re.compile(r'user_pref\("([^"]+)",\s*(.+?)\);')
        
        matches = pattern.findall(content)
        for name, val_str in matches:
            # clean up value string
            val_str = val_str.strip()
            
            # Convert to python types
            if val_str == 'true':
                val = True
            elif val_str == 'false':
                val = False
            elif val_str.startswith('"') and val_str.endswith('"'):
                val = val_str[1:-1] # strip quotes
            else:
                try:
                    val = int(val_str)
                except ValueError:
                    val = val_str # fallback
            
            result["actual_prefs"][name] = val
            
    except Exception as e:
        result["error_reading_prefs"] = str(e)
else:
    result["error_reading_prefs"] = "prefs.js not found"

# 2. Parse User Report JSON
if os.path.exists(report_file):
    try:
        with open(report_file, 'r') as f:
            result["report_content"] = json.load(f)
    except Exception as e:
        result["report_valid_json"] = False
        result["report_error"] = str(e)
else:
    result["report_content"] = None

# Save result
with open(output_json, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Exported result to {output_json}")
EOF

# 6. Move result to safe location and set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="