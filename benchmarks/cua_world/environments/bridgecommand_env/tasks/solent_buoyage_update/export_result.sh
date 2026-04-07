#!/bin/bash
echo "=== Exporting Solent Buoyage Update Results ==="

# 1. Timestamp Check
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 2. Find the new world directory
WORLD_BASE="/opt/bridgecommand/World"
TARGET_DIR="$WORLD_BASE/Solent_v2026"

DIR_EXISTS="false"
DESC_UPDATED="false"
BUOY_INI_CONTENT=""
LIGHT_INI_CONTENT=""
GROUND_TRUTH_CONTENT="{}"

if [ -d "$TARGET_DIR" ]; then
    DIR_EXISTS="true"
    
    # Check description.ini
    if [ -f "$TARGET_DIR/description.ini" ]; then
        if grep -q "2026" "$TARGET_DIR/description.ini"; then
            DESC_UPDATED="true"
        fi
    fi

    # Read INI files content (limited size for safety)
    if [ -f "$TARGET_DIR/buoy.ini" ]; then
        BUOY_INI_CONTENT=$(cat "$TARGET_DIR/buoy.ini" | head -n 500)
    fi
    
    if [ -f "$TARGET_DIR/light.ini" ]; then
        LIGHT_INI_CONTENT=$(cat "$TARGET_DIR/light.ini" | head -n 500)
    fi
fi

# 3. Read Ground Truth (requires root usually, so we do it here in the export script)
if [ -f "/var/lib/bridgecommand/task_data/ground_truth.json" ]; then
    GROUND_TRUTH_CONTENT=$(cat "/var/lib/bridgecommand/task_data/ground_truth.json")
fi

# 4. Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create JSON Result using Python for safe escaping
python3 -c "
import json
import os

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'dir_exists': $DIR_EXISTS,
    'desc_updated': $DESC_UPDATED,
    'buoy_ini': '''$BUOY_INI_CONTENT''',
    'light_ini': '''$LIGHT_INI_CONTENT''',
    'ground_truth': $GROUND_TRUTH_CONTENT
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# Set permissions so verifier can copy it
chmod 644 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"