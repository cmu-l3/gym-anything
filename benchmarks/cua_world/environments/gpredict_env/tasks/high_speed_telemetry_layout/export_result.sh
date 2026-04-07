#!/bin/bash
echo "=== Exporting high_speed_telemetry_layout result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
MOD_PATH="${GPREDICT_CONF_DIR}/modules/Physics_Telemetry.mod"
QTH_PATH="${GPREDICT_CONF_DIR}/Tromso.qth"
CFG_PATH="${GPREDICT_CONF_DIR}/gpredict.cfg"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || true

# Fallback path checking (case insensitivity)
if [ ! -f "$MOD_PATH" ]; then
    for f in "${GPREDICT_CONF_DIR}"/modules/*.mod; do
        if echo "$f" | grep -qi "physics.*telemetry"; then
            MOD_PATH="$f"
            break
        fi
    done
fi

if [ ! -f "$QTH_PATH" ]; then
    for f in "${GPREDICT_CONF_DIR}"/*.qth; do
        if echo "$f" | grep -qi "tromso"; then
            QTH_PATH="$f"
            break
        fi
    done
fi

# Encode files as base64 to safely transport INI contents through JSON
MOD_B64=$( [ -f "$MOD_PATH" ] && base64 -w 0 "$MOD_PATH" || echo "" )
QTH_B64=$( [ -f "$QTH_PATH" ] && base64 -w 0 "$QTH_PATH" || echo "" )
CFG_B64=$( [ -f "$CFG_PATH" ] && base64 -w 0 "$CFG_PATH" || echo "" )

# Check file modification times for anti-gaming
MOD_MTIME=$( [ -f "$MOD_PATH" ] && stat -c %Y "$MOD_PATH" || echo "0" )
QTH_MTIME=$( [ -f "$QTH_PATH" ] && stat -c %Y "$QTH_PATH" || echo "0" )

# Create JSON result using a temp file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "mod_mtime": $MOD_MTIME,
    "qth_mtime": $QTH_MTIME,
    "mod_b64": "$MOD_B64",
    "qth_b64": "$QTH_B64",
    "cfg_b64": "$CFG_B64",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="