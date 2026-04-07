#!/bin/bash
# Export script for ag_drought_monitoring_setup task

echo "=== Exporting ag_drought_monitoring_setup result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"
TASK_START_TIMESTAMP=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# --- Check if Old_HQ was deleted ---
OLD_HQ_EXISTS="false"
if ls "${GPREDICT_CONF_DIR}"/Old_HQ.qth 1> /dev/null 2>&1 || ls "${GPREDICT_CONF_DIR}"/old_hq.qth 1> /dev/null 2>&1; then
    OLD_HQ_EXISTS="true"
fi

# --- Helper function to parse QTH files ---
parse_qth() {
    local qth_file="$1"
    local prefix="$2"
    
    if [ -f "$qth_file" ]; then
        eval "${prefix}_EXISTS=\"true\""
        eval "${prefix}_LAT=\"\$(grep -i '^LAT=' '$qth_file' | head -1 | cut -d= -f2 | tr -d '[:space:]')\""
        eval "${prefix}_LON=\"\$(grep -i '^LON=' '$qth_file' | head -1 | cut -d= -f2 | tr -d '[:space:]')\""
        eval "${prefix}_ALT=\"\$(grep -i '^ALT=' '$qth_file' | head -1 | cut -d= -f2 | tr -d '[:space:]')\""
        eval "${prefix}_WX=\"\$(grep -i '^WX=' '$qth_file' | head -1 | cut -d= -f2 | tr -d '[:space:]')\""
        
        # Check creation/modification time
        local mtime=$(stat -c %Y "$qth_file" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START_TIMESTAMP" ]; then
            eval "${prefix}_CREATED_DURING_TASK=\"true\""
        else
            eval "${prefix}_CREATED_DURING_TASK=\"false\""
        fi
    else
        eval "${prefix}_EXISTS=\"false\""
        eval "${prefix}_CREATED_DURING_TASK=\"false\""
    fi
}

# --- Read Iowa Test Farm QTH ---
IOWA_QTH_FILE=$(ls "${GPREDICT_CONF_DIR}"/*iowa*.qth 2>/dev/null | head -1)
if [ -z "$IOWA_QTH_FILE" ]; then
    IOWA_QTH_FILE="${GPREDICT_CONF_DIR}/Iowa_Test_Farm.qth" # Fallback to check directly
fi
parse_qth "$IOWA_QTH_FILE" "IOWA"

# --- Read Nebraska Site QTH ---
NEBRASKA_QTH_FILE=$(ls "${GPREDICT_CONF_DIR}"/*nebraska*.qth 2>/dev/null | head -1)
if [ -z "$NEBRASKA_QTH_FILE" ]; then
    NEBRASKA_QTH_FILE="${GPREDICT_CONF_DIR}/Nebraska_Site.qth"
fi
parse_qth "$NEBRASKA_QTH_FILE" "NEBRASKA"

# --- Read Drought_Monitor.mod ---
MODULE_EXISTS="false"
MODULE_CREATED_DURING_TASK="false"
MODULE_SATELLITES=""
MODULE_HAS_NOAA19="false"
MODULE_HAS_NOAA20="false"
MODULE_HAS_SUOMI="false"
MODULE_HAS_METOPB="false"
MODULE_HAS_METOPC="false"

DROUGHT_MOD_FILE=$(ls "${GPREDICT_MOD_DIR}"/*drought*.mod 2>/dev/null | head -1)
if [ -n "$DROUGHT_MOD_FILE" ] && [ -f "$DROUGHT_MOD_FILE" ]; then
    MODULE_EXISTS="true"
    MODULE_SATELLITES=$(grep -i "^SATELLITES=" "$DROUGHT_MOD_FILE" | head -1 | cut -d= -f2)
    
    if echo "$MODULE_SATELLITES" | grep -q "33591"; then MODULE_HAS_NOAA19="true"; fi
    if echo "$MODULE_SATELLITES" | grep -q "43013"; then MODULE_HAS_NOAA20="true"; fi
    if echo "$MODULE_SATELLITES" | grep -q "37849"; then MODULE_HAS_SUOMI="true"; fi
    if echo "$MODULE_SATELLITES" | grep -q "38771"; then MODULE_HAS_METOPB="true"; fi
    if echo "$MODULE_SATELLITES" | grep -q "43689"; then MODULE_HAS_METOPC="true"; fi
    
    local mod_mtime=$(stat -c %Y "$DROUGHT_MOD_FILE" 2>/dev/null || echo "0")
    if [ "$mod_mtime" -gt "$TASK_START_TIMESTAMP" ]; then
        MODULE_CREATED_DURING_TASK="true"
    fi
fi

# --- Check Default QTH in gpredict.cfg ---
DEFAULT_QTH_IS_IOWA="false"
GPREDICT_CFG="${GPREDICT_CONF_DIR}/gpredict.cfg"
GPREDICT_CFG_CONTENT=""

if [ -f "$GPREDICT_CFG" ]; then
    DEFAULT_QTH_VAL=$(grep -i "^DEFAULT_QTH=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    # Check if the value contains 'iowa' (case insensitive)
    if echo "$DEFAULT_QTH_VAL" | grep -qi "iowa"; then
        DEFAULT_QTH_IS_IOWA="true"
    fi
    GPREDICT_CFG_CONTENT=$(cat "$GPREDICT_CFG" | tr '\n' '|' | sed 's/"/\\"/g')
fi

# --- Escape JSON values ---
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/ag_drought_monitoring_setup_result.json << EOF
{
    "task_start_timestamp": $TASK_START_TIMESTAMP,
    "old_hq_exists": $OLD_HQ_EXISTS,
    "iowa_exists": $IOWA_EXISTS,
    "iowa_lat": "$(escape_json "$IOWA_LAT")",
    "iowa_lon": "$(escape_json "$IOWA_LON")",
    "iowa_alt": "$(escape_json "$IOWA_ALT")",
    "iowa_wx": "$(escape_json "$IOWA_WX")",
    "iowa_created_during_task": $IOWA_CREATED_DURING_TASK,
    "nebraska_exists": $NEBRASKA_EXISTS,
    "nebraska_lat": "$(escape_json "$NEBRASKA_LAT")",
    "nebraska_lon": "$(escape_json "$NEBRASKA_LON")",
    "nebraska_alt": "$(escape_json "$NEBRASKA_ALT")",
    "nebraska_wx": "$(escape_json "$NEBRASKA_WX")",
    "nebraska_created_during_task": $NEBRASKA_CREATED_DURING_TASK,
    "module_exists": $MODULE_EXISTS,
    "module_created_during_task": $MODULE_CREATED_DURING_TASK,
    "module_satellites": "$(escape_json "$MODULE_SATELLITES")",
    "module_has_noaa19": $MODULE_HAS_NOAA19,
    "module_has_noaa20": $MODULE_HAS_NOAA20,
    "module_has_suomi": $MODULE_HAS_SUOMI,
    "module_has_metopb": $MODULE_HAS_METOPB,
    "module_has_metopc": $MODULE_HAS_METOPC,
    "default_qth_is_iowa": $DEFAULT_QTH_IS_IOWA,
    "gpredict_cfg_content": "$(escape_json "$GPREDICT_CFG_CONTENT")",
    "export_timestamp": "$(date +%s)"
}
EOF

echo "Result saved to /tmp/ag_drought_monitoring_setup_result.json"
cat /tmp/ag_drought_monitoring_setup_result.json
echo ""
echo "=== Export Complete ==="