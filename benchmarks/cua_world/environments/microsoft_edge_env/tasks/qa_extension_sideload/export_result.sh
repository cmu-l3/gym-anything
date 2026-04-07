#!/bin/bash
echo "=== Exporting Results for QA Extension Sideload ==="

# 1. Take final screenshot (CRITICAL for VLM)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Kill Edge to force flush of Preferences file to disk
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
# Wait for process to exit and file write
sleep 3

# 3. Parse Preferences file to extract extension state
PREFS_FILE="/home/ga/.config/microsoft-edge/Default/Preferences"
EXT_PATH="/home/ga/Documents/BugReporter_v2"

# We use python to safely parse the huge JSON file
python3 <<PYEOF
import json
import os
import sys

result = {
    "prefs_exists": False,
    "dev_mode_enabled": False,
    "extension_loaded": False,
    "extension_id": None,
    "pinned_extensions": []
}

prefs_path = "$PREFS_FILE"
target_path = "$EXT_PATH"

if os.path.exists(prefs_path):
    result["prefs_exists"] = True
    try:
        with open(prefs_path, 'r') as f:
            data = json.load(f)
        
        # Check Developer Mode
        # Usually extensions.ui.developer_mode = true
        extensions = data.get('extensions', {})
        ui = extensions.get('ui', {})
        result["dev_mode_enabled"] = ui.get('developer_mode', False)

        # Check for loaded extension
        settings = extensions.get('settings', {})
        for ext_id, ext_data in settings.items():
            # Unpacked extensions have a 'path' property
            if ext_data.get('path') == target_path:
                result["extension_loaded"] = True
                result["extension_id"] = ext_id
                break
        
        # Check for pinned extensions
        # Location varies by Chromium version, often in 'extensions.pinned_extensions' 
        # or 'extensions.toolbar' or 'browser.action_toolbar'
        pinned = extensions.get('pinned_extensions', [])
        
        # Also check 'toolbar' list if pinned_extensions is empty/missing
        if not pinned:
            toolbar = extensions.get('toolbar', [])
            if isinstance(toolbar, list):
                pinned = toolbar
        
        result["pinned_extensions"] = pinned

    except Exception as e:
        result["error"] = str(e)

# Write result to /tmp/task_result.json
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export logic complete.")
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="