#!/bin/bash
echo "=== Exporting disable_station_picking results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Paths
ETC_KEY_DIR="$SEISCOMP_ROOT/etc/key"
HOME_KEY_DIR="/home/ga/.seiscomp/key"

# Helper function to check if a specific binding exists for a station
check_binding() {
    local station="$1"
    local module="$2"
    local etc_file="$ETC_KEY_DIR/station_${station}"
    local home_file="$HOME_KEY_DIR/station_${station}"
    
    # Check both the global config directory and the user-specific directory
    if [ -f "$etc_file" ] && grep -q "$module" "$etc_file"; then
        echo "true"
        return
    fi
    if [ -f "$home_file" ] && grep -q "$module" "$home_file"; then
        echo "true"
        return
    fi
    echo "false"
}

# 1. Target Station (GE_KWP) checks
TARGET_STA="GE_KWP"
KWP_EXISTS="false"
if [ -f "$ETC_KEY_DIR/station_${TARGET_STA}" ] || [ -f "$HOME_KEY_DIR/station_${TARGET_STA}" ]; then
    KWP_EXISTS="true"
fi

KWP_HAS_AUTOPICK=$(check_binding "$TARGET_STA" "scautopick")
KWP_HAS_GLOBAL=$(check_binding "$TARGET_STA" "global")

# 2. Control Station (GE_TOLI) checks
CONTROL_STA="GE_TOLI"
TOLI_EXISTS="false"
if [ -f "$ETC_KEY_DIR/station_${CONTROL_STA}" ] || [ -f "$HOME_KEY_DIR/station_${CONTROL_STA}" ]; then
    TOLI_EXISTS="true"
fi

TOLI_HAS_AUTOPICK=$(check_binding "$CONTROL_STA" "scautopick")

# 3. Service Status Check
SCAUTOPICK_RUNNING="false"
if su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH seiscomp status scautopick" | grep -q "is running"; then
    SCAUTOPICK_RUNNING="true"
fi

# 4. Detect file modifications
KWP_MODIFIED_TIME=$(stat -c %Y "$ETC_KEY_DIR/station_${TARGET_STA}" 2>/dev/null || echo "0")
if [ -f "$HOME_KEY_DIR/station_${TARGET_STA}" ]; then
    HOME_KWP_MOD_TIME=$(stat -c %Y "$HOME_KEY_DIR/station_${TARGET_STA}" 2>/dev/null || echo "0")
    if [ "$HOME_KWP_MOD_TIME" -gt "$KWP_MODIFIED_TIME" ]; then
        KWP_MODIFIED_TIME=$HOME_KWP_MOD_TIME
    fi
fi

FILE_MODIFIED_DURING_TASK="false"
if [ "$KWP_MODIFIED_TIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED_DURING_TASK="true"
fi

# Write results to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "kwp_exists": $KWP_EXISTS,
    "kwp_has_autopick": $KWP_HAS_AUTOPICK,
    "kwp_has_global": $KWP_HAS_GLOBAL,
    "toli_exists": $TOLI_EXISTS,
    "toli_has_autopick": $TOLI_HAS_AUTOPICK,
    "scautopick_running": $SCAUTOPICK_RUNNING,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK
}
EOF

# Move securely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json