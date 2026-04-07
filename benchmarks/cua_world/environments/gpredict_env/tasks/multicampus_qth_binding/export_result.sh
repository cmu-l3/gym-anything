#!/bin/bash
# Export script for multicampus_qth_binding task

echo "=== Exporting multicampus_qth_binding result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || true

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

# Parse a QTH file and return a JSON fragment
parse_qth() {
    local qth_name="$1"
    local qth_file=""
    
    # Case-insensitive search for the QTH file
    for f in "${GPREDICT_CONF_DIR}"/*.qth; do
        [ -f "$f" ] || continue
        if echo "$(basename "$f")" | grep -qi "^${qth_name}\.qth$"; then
            qth_file="$f"
            break
        fi
    done

    if [ -n "$qth_file" ]; then
        local lat=$(grep -i "^LAT=" "$qth_file" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        local lon=$(grep -i "^LON=" "$qth_file" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        local alt=$(grep -i "^ALT=" "$qth_file" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        local mtime=$(stat -c %Y "$qth_file" 2>/dev/null || echo "0")
        echo "\"exists\": true, \"lat\": \"$(escape_json "$lat")\", \"lon\": \"$(escape_json "$lon")\", \"alt\": \"$(escape_json "$alt")\", \"mtime\": $mtime, \"filename\": \"$(escape_json "$(basename "$qth_file")")\""
    else
        echo "\"exists\": false, \"lat\": \"\", \"lon\": \"\", \"alt\": \"\", \"mtime\": 0, \"filename\": \"\""
    fi
}

# Parse a MOD file and return a JSON fragment
parse_mod() {
    local mod_name="$1"
    local mod_file=""
    
    # Case-insensitive search for the MOD file
    for f in "${GPREDICT_MOD_DIR}"/*.mod; do
        [ -f "$f" ] || continue
        if echo "$(basename "$f")" | grep -qi "^${mod_name}\.mod$"; then
            mod_file="$f"
            break
        fi
    done

    if [ -n "$mod_file" ]; then
        local satellites=$(grep -i "^SATELLITES=" "$mod_file" | head -1 | cut -d= -f2 | tr -d '\n\r')
        local qthfile=$(grep -i "^QTHFILE=" "$mod_file" | head -1 | cut -d= -f2 | tr -d '\n\r')
        # Some versions might just use QTH=
        if [ -z "$qthfile" ]; then
            qthfile=$(grep -i "^QTH=" "$mod_file" | head -1 | cut -d= -f2 | tr -d '\n\r')
        fi
        local mtime=$(stat -c %Y "$mod_file" 2>/dev/null || echo "0")
        echo "\"exists\": true, \"satellites\": \"$(escape_json "$satellites")\", \"qthfile\": \"$(escape_json "$qthfile")\", \"mtime\": $mtime, \"filename\": \"$(escape_json "$(basename "$mod_file")")\""
    else
        echo "\"exists\": false, \"satellites\": \"\", \"qthfile\": \"\", \"mtime\": 0, \"filename\": \"\""
    fi
}

# Get task start time
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Read gpredict.cfg
DEFAULT_QTH=""
UTC_ENABLED="false"
GPREDICT_CFG="${GPREDICT_CONF_DIR}/gpredict.cfg"
if [ -f "$GPREDICT_CFG" ]; then
    DEFAULT_QTH=$(grep -i "^DEFAULT_QTH=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '\n\r')
    UTC_VAL=$(grep -i "^utc=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    if [ "$UTC_VAL" = "1" ]; then
        UTC_ENABLED="true"
    fi
fi

# Build JSON Result
TEMP_JSON=$(mktemp /tmp/multicampus_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "qth_cu_boulder": { $(parse_qth "CU_Boulder") },
    "qth_csu_fortcollins": { $(parse_qth "CSU_FortCollins") },
    "qth_mines_golden": { $(parse_qth "Mines_Golden") },
    "mod_cu_boulder": { $(parse_mod "CU_Boulder") },
    "mod_csu_fortcollins": { $(parse_mod "CSU_FortCollins") },
    "mod_mines_golden": { $(parse_mod "Mines_Golden") },
    "cfg_default_qth": "$(escape_json "$DEFAULT_QTH")",
    "cfg_utc_enabled": $UTC_ENABLED,
    "export_timestamp": $(date +%s)
}
EOF

# Move to safe location
rm -f /tmp/multicampus_qth_binding_result.json 2>/dev/null || sudo rm -f /tmp/multicampus_qth_binding_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/multicampus_qth_binding_result.json
chmod 666 /tmp/multicampus_qth_binding_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/multicampus_qth_binding_result.json"
cat /tmp/multicampus_qth_binding_result.json
echo ""
echo "=== Export Complete ==="