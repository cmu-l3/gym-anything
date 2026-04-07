#!/bin/bash
# Export script for pacific_tsunami_wx_network task
# Extracts all ground station and module details into JSON for the verifier

echo "=== Exporting pacific_tsunami_wx_network result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final_state.png 2>/dev/null || true

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

# --- Extract all QTH (Ground Station) files ---
QTH_JSON="["
FIRST="true"
for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    name=$(basename "$qth" .qth)
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]' | tr -d '\r')
    lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]' | tr -d '\r')
    alt=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]' | tr -d '\r')
    mtime=$(stat -c %Y "$qth" 2>/dev/null || echo 0)
    
    if [ "$FIRST" = "true" ]; then FIRST="false"; else QTH_JSON="$QTH_JSON,"; fi
    QTH_JSON="$QTH_JSON {\"name\": \"$(escape_json "$name")\", \"lat\": \"$lat\", \"lon\": \"$lon\", \"alt\": \"$alt\", \"mtime\": $mtime}"
done
QTH_JSON="$QTH_JSON]"

# --- Extract all Module files ---
MOD_JSON="["
FIRST="true"
for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    name=$(basename "$mod" .mod)
    sats=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2 | tr -d '[:space:]' | tr -d '\r')
    mtime=$(stat -c %Y "$mod" 2>/dev/null || echo 0)
    
    if [ "$FIRST" = "true" ]; then FIRST="false"; else MOD_JSON="$MOD_JSON,"; fi
    MOD_JSON="$MOD_JSON {\"name\": \"$(escape_json "$name")\", \"satellites\": \"$(escape_json "$sats")\", \"mtime\": $mtime}"
done
MOD_JSON="$MOD_JSON]"

# --- Extract Global Config ---
DEFAULT_QTH=""
METRIC_UNITS="false"
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    DEFAULT_QTH=$(grep -i "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg" | head -1 | cut -d= -f2 | tr -d '[:space:]' | tr -d '\r')
    UNIT_VAL=$(grep -i "^unit=" "${GPREDICT_CONF_DIR}/gpredict.cfg" | head -1 | cut -d= -f2 | tr -d '[:space:]' | tr -d '\r')
    if [ "$UNIT_VAL" = "0" ]; then
        METRIC_UNITS="true"
    fi
fi

# Output JSON
cat > /tmp/pacific_tsunami_wx_network_result.json << EOF
{
    "qth_files": $QTH_JSON,
    "modules": $MOD_JSON,
    "default_qth": "$(escape_json "$DEFAULT_QTH")",
    "metric_units": $METRIC_UNITS,
    "task_start_time": $(cat /tmp/task_start_time.txt 2>/dev/null || echo 0),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/pacific_tsunami_wx_network_result.json"
echo "=== Export Complete ==="