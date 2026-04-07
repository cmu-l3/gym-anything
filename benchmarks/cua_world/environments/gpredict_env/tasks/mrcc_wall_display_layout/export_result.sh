#!/bin/bash
set -e

echo "=== Exporting mrcc_wall_display_layout result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || true

# --- Find Malta QTH ---
QTH_FILE=""
QTH_CREATED_DURING_TASK="false"

# Look for MRCC_Malta or any QTH created around Malta coordinates
for f in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$f" ] || continue
    # Skip standard Pittsburgh
    if echo "$f" | grep -qi "pittsburgh"; then continue; fi
    
    # Check if filename contains Malta OR lat matches ~35.9
    if echo "$f" | grep -qi "malta" || grep -qi "^LAT=35\.9" "$f"; then
        QTH_FILE="$f"
        break
    fi
done

QTH_B64=""
if [ -n "$QTH_FILE" ] && [ -f "$QTH_FILE" ]; then
    QTH_MTIME=$(stat -c %Y "$QTH_FILE" 2>/dev/null || echo "0")
    if [ "$QTH_MTIME" -gt "$TASK_START" ]; then
        QTH_CREATED_DURING_TASK="true"
    fi
    # Use Base64 encoding to safely pass multiline INI file content in JSON
    QTH_B64=$(base64 -w 0 "$QTH_FILE")
fi

# --- Find SAR Module ---
MOD_FILE=""
MOD_CREATED_DURING_TASK="false"

# Look for SAR_Wall_Display or similar
for f in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$f" ] || continue
    # Skip standard Amateur
    if echo "$f" | grep -qi "amateur"; then continue; fi
    
    if echo "$f" | grep -qi "sar\|wall\|display\|mrcc"; then
        MOD_FILE="$f"
        break
    fi
done

MOD_B64=""
if [ -n "$MOD_FILE" ] && [ -f "$MOD_FILE" ]; then
    MOD_MTIME=$(stat -c %Y "$MOD_FILE" 2>/dev/null || echo "0")
    if [ "$MOD_MTIME" -gt "$TASK_START" ]; then
        MOD_CREATED_DURING_TASK="true"
    fi
    # Use Base64 encoding
    MOD_B64=$(base64 -w 0 "$MOD_FILE")
fi

# Create Result JSON securely
TEMP_JSON=$(mktemp /tmp/mrcc_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "qth_found": $([ -n "$QTH_FILE" ] && echo "true" || echo "false"),
    "qth_filename": "$(basename "$QTH_FILE" 2>/dev/null || echo "")",
    "qth_created_during_task": $QTH_CREATED_DURING_TASK,
    "qth_content_b64": "$QTH_B64",
    "mod_found": $([ -n "$MOD_FILE" ] && echo "true" || echo "false"),
    "mod_filename": "$(basename "$MOD_FILE" 2>/dev/null || echo "")",
    "mod_created_during_task": $MOD_CREATED_DURING_TASK,
    "mod_content_b64": "$MOD_B64",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="