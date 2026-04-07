#!/bin/bash
echo "=== Exporting alpine_wildfire_tracking result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# --- Find the Santiago ground station ---
SANTIAGO_EXISTS="false"
SANTIAGO_QTH_FILE=""
SANTIAGO_QTH_CONTENT=""
SANTIAGO_CREATED_DURING_TASK="false"

# Look for any QTH file containing 'santiago' (case-insensitive)
for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth")
    if echo "$basename_qth" | grep -qi "santiago"; then
        SANTIAGO_EXISTS="true"
        SANTIAGO_QTH_FILE="$basename_qth"
        # Extract content replacing newlines with pipes for JSON safety
        SANTIAGO_QTH_CONTENT=$(cat "$qth" | tr '\n' '|' | tr -d '\r')
        
        # Check timestamp
        MTIME=$(stat -c %Y "$qth" 2>/dev/null || echo "0")
        if [ "$MTIME" -ge "$TASK_START" ]; then
            SANTIAGO_CREATED_DURING_TASK="true"
        fi
        break
    fi
done

# --- Find the Fire_Orbits module ---
FIRE_EXISTS="false"
FIRE_MOD_FILE=""
FIRE_MOD_CONTENT=""
FIRE_CREATED_DURING_TASK="false"

# Look for any MOD file containing 'fire' or 'orbit' (case-insensitive)
for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    basename_mod=$(basename "$mod")
    if echo "$basename_mod" | grep -qi "fire\|orbit"; then
        FIRE_EXISTS="true"
        FIRE_MOD_FILE="$basename_mod"
        FIRE_MOD_CONTENT=$(cat "$mod" | tr '\n' '|' | tr -d '\r')
        
        # Check timestamp
        MTIME=$(stat -c %Y "$mod" 2>/dev/null || echo "0")
        if [ "$MTIME" -ge "$TASK_START" ]; then
            FIRE_CREATED_DURING_TASK="true"
        fi
        break
    fi
done

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

SANTIAGO_QTH_CONTENT_ESC=$(escape_json "$SANTIAGO_QTH_CONTENT")
FIRE_MOD_CONTENT_ESC=$(escape_json "$FIRE_MOD_CONTENT")

cat > /tmp/alpine_wildfire_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "santiago_exists": $SANTIAGO_EXISTS,
    "santiago_qth_file": "$(escape_json "$SANTIAGO_QTH_FILE")",
    "santiago_created_during_task": $SANTIAGO_CREATED_DURING_TASK,
    "santiago_qth_content": "$SANTIAGO_QTH_CONTENT_ESC",
    "fire_mod_exists": $FIRE_EXISTS,
    "fire_mod_file": "$(escape_json "$FIRE_MOD_FILE")",
    "fire_mod_created_during_task": $FIRE_CREATED_DURING_TASK,
    "fire_mod_content": "$FIRE_MOD_CONTENT_ESC",
    "export_timestamp": "$(date +%s)"
}
EOF

echo "Result saved to /tmp/alpine_wildfire_result.json"
echo "=== Export Complete ==="