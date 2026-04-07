#!/bin/bash
# Export script for gnss_canyon_survey_planning task

echo "=== Exporting gnss_canyon_survey_planning result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Check if GPredict is still running
APP_RUNNING="false"
if pgrep -x gpredict > /dev/null; then
    APP_RUNNING="true"
fi

# --- 1. Check Amateur.mod ---
AMATEUR_EXISTS="false"
if [ -f "${GPREDICT_MOD_DIR}/Amateur.mod" ]; then
    AMATEUR_EXISTS="true"
fi

# --- 2. Check Zion_Canyon.qth ---
ZION_EXISTS="false"
ZION_CONTENT=""
ZION_MTIME=0
# Search for the qth by filename or coordinate approximation
for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    
    if echo "$basename_qth" | grep -qi "zion"; then
        ZION_EXISTS="true"
        ZION_CONTENT=$(cat "$qth" | tr '\n' '|' | sed 's/"/\\"/g')
        ZION_MTIME=$(stat -c %Y "$qth")
        break
    fi
    
    # Fallback: Check if coordinates match
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]' | cut -d. -f1)
    if [ "$lat" = "37" ]; then
        lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]' | sed 's/-//' | cut -d. -f1)
        if [ "$lon" = "113" ]; then
            ZION_EXISTS="true"
            ZION_CONTENT=$(cat "$qth" | tr '\n' '|' | sed 's/"/\\"/g')
            ZION_MTIME=$(stat -c %Y "$qth")
            break
        fi
    fi
done

# --- 3. Check GNSS_Survey.mod ---
GNSS_EXISTS="false"
GNSS_CONTENT=""
GNSS_MTIME=0

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    
    if echo "$modname" | grep -qi "gnss\|survey"; then
        GNSS_EXISTS="true"
        GNSS_CONTENT=$(cat "$mod" | tr '\n' '|' | sed 's/"/\\"/g')
        GNSS_MTIME=$(stat -c %Y "$mod")
        break
    fi
done

# --- 4. Check gpredict.cfg for MIN_EL ---
CFG_CONTENT=""
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    CFG_CONTENT=$(cat "${GPREDICT_CONF_DIR}/gpredict.cfg" | tr '\n' '|' | sed 's/"/\\"/g')
fi

# Load task start timestamp for anti-gaming
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "app_running": $APP_RUNNING,
    "amateur_exists": $AMATEUR_EXISTS,
    "zion_exists": $ZION_EXISTS,
    "zion_content": "$ZION_CONTENT",
    "zion_mtime": $ZION_MTIME,
    "gnss_exists": $GNSS_EXISTS,
    "gnss_content": "$GNSS_CONTENT",
    "gnss_mtime": $GNSS_MTIME,
    "cfg_content": "$CFG_CONTENT"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="