#!/bin/bash
# Export script for dsn_multisite_visibility task

echo "=== Exporting dsn_multisite_visibility result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Initialize variables
GOLDSTONE_QTH_FILE=""; GOLDSTONE_LAT=""; GOLDSTONE_LON=""; GOLDSTONE_ALT=""; GOLDSTONE_MTIME="0"
MADRID_QTH_FILE=""; MADRID_LAT=""; MADRID_LON=""; MADRID_ALT=""; MADRID_MTIME="0"
CANBERRA_QTH_FILE=""; CANBERRA_LAT=""; CANBERRA_LON=""; CANBERRA_ALT=""; CANBERRA_MTIME="0"

# --- 1. Find Ground Stations by Coordinates ---
for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth")
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    alt=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    mtime=$(stat -c %Y "$qth" 2>/dev/null || echo "0")
    
    # Goldstone (~35.4N, -116.8W)
    if echo "$lat" | grep -q "^35"; then
        if echo "$lon" | grep -q "^-116"; then
            GOLDSTONE_QTH_FILE="$basename_qth"
            GOLDSTONE_LAT="$lat"
            GOLDSTONE_LON="$lon"
            GOLDSTONE_ALT="$alt"
            GOLDSTONE_MTIME="$mtime"
            continue
        fi
    fi
    
    # Madrid (~40.4N, -3.9W)
    if echo "$lat" | grep -q "^40"; then
        if echo "$lon" | grep -q "^-3" || echo "$lon" | grep -q "^-4"; then
            MADRID_QTH_FILE="$basename_qth"
            MADRID_LAT="$lat"
            MADRID_LON="$lon"
            MADRID_ALT="$alt"
            MADRID_MTIME="$mtime"
            continue
        fi
    fi
    
    # Canberra (~-35.4S, 148.9E)
    if echo "$lat" | grep -q "^-35"; then
        if echo "$lon" | grep -q "^148" || echo "$lon" | grep -q "^149"; then
            CANBERRA_QTH_FILE="$basename_qth"
            CANBERRA_LAT="$lat"
            CANBERRA_LON="$lon"
            CANBERRA_ALT="$alt"
            CANBERRA_MTIME="$mtime"
            continue
        fi
    fi
done

# --- 2. Find Modules by Name ---
MOD_GOLDSTONE_FILE=""; MOD_GOLDSTONE_SATS=""; MOD_GOLDSTONE_QTH=""; MOD_GOLDSTONE_MTIME="0"
MOD_MADRID_FILE=""; MOD_MADRID_SATS=""; MOD_MADRID_QTH=""; MOD_MADRID_MTIME="0"
MOD_CANBERRA_FILE=""; MOD_CANBERRA_SATS=""; MOD_CANBERRA_QTH=""; MOD_CANBERRA_MTIME="0"

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod")
    modname_lower=$(echo "$modname" | tr '[:upper:]' '[:lower:]')
    
    sats=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
    qth_mapping=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    mtime=$(stat -c %Y "$mod" 2>/dev/null || echo "0")
    
    if echo "$modname_lower" | grep -q "goldstone"; then
        MOD_GOLDSTONE_FILE="$modname"
        MOD_GOLDSTONE_SATS="$sats"
        MOD_GOLDSTONE_QTH="$qth_mapping"
        MOD_GOLDSTONE_MTIME="$mtime"
    elif echo "$modname_lower" | grep -q "madrid"; then
        MOD_MADRID_FILE="$modname"
        MOD_MADRID_SATS="$sats"
        MOD_MADRID_QTH="$qth_mapping"
        MOD_MADRID_MTIME="$mtime"
    elif echo "$modname_lower" | grep -q "canberra"; then
        MOD_CANBERRA_FILE="$modname"
        MOD_CANBERRA_SATS="$sats"
        MOD_CANBERRA_QTH="$qth_mapping"
        MOD_CANBERRA_MTIME="$mtime"
    fi
done

# --- 3. Check UTC Time Setting ---
UTC_TIME_ENABLED="false"
GPREDICT_CFG="${GPREDICT_CONF_DIR}/gpredict.cfg"
GPREDICT_CFG_CONTENT=""
if [ -f "$GPREDICT_CFG" ]; then
    GPREDICT_CFG_CONTENT=$(cat "$GPREDICT_CFG" | tr '\n' '|' | sed 's/"/\\"/g')
    # UTC mode is often unit=1 or use_local_time=0 or utc=1 depending on version
    if grep -qi "utc=1" "$GPREDICT_CFG" || grep -qi "use_local_time=0" "$GPREDICT_CFG" || grep -qi "time_format=1" "$GPREDICT_CFG"; then
        UTC_TIME_ENABLED="true"
    fi
fi

# Utility to escape JSON strings safely
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/dsn_multisite_visibility_result.json << EOF
{
    "task_start_time": $TASK_START_TIME,
    
    "goldstone_qth_file": "$(escape_json "$GOLDSTONE_QTH_FILE")",
    "goldstone_lat": "$(escape_json "$GOLDSTONE_LAT")",
    "goldstone_lon": "$(escape_json "$GOLDSTONE_LON")",
    "goldstone_alt": "$(escape_json "$GOLDSTONE_ALT")",
    "goldstone_mtime": $GOLDSTONE_MTIME,
    
    "madrid_qth_file": "$(escape_json "$MADRID_QTH_FILE")",
    "madrid_lat": "$(escape_json "$MADRID_LAT")",
    "madrid_lon": "$(escape_json "$MADRID_LON")",
    "madrid_alt": "$(escape_json "$MADRID_ALT")",
    "madrid_mtime": $MADRID_MTIME,
    
    "canberra_qth_file": "$(escape_json "$CANBERRA_QTH_FILE")",
    "canberra_lat": "$(escape_json "$CANBERRA_LAT")",
    "canberra_lon": "$(escape_json "$CANBERRA_LON")",
    "canberra_alt": "$(escape_json "$CANBERRA_ALT")",
    "canberra_mtime": $CANBERRA_MTIME,
    
    "mod_goldstone_file": "$(escape_json "$MOD_GOLDSTONE_FILE")",
    "mod_goldstone_sats": "$(escape_json "$MOD_GOLDSTONE_SATS")",
    "mod_goldstone_qth": "$(escape_json "$MOD_GOLDSTONE_QTH")",
    "mod_goldstone_mtime": $MOD_GOLDSTONE_MTIME,
    
    "mod_madrid_file": "$(escape_json "$MOD_MADRID_FILE")",
    "mod_madrid_sats": "$(escape_json "$MOD_MADRID_SATS")",
    "mod_madrid_qth": "$(escape_json "$MOD_MADRID_QTH")",
    "mod_madrid_mtime": $MOD_MADRID_MTIME,
    
    "mod_canberra_file": "$(escape_json "$MOD_CANBERRA_FILE")",
    "mod_canberra_sats": "$(escape_json "$MOD_CANBERRA_SATS")",
    "mod_canberra_qth": "$(escape_json "$MOD_CANBERRA_QTH")",
    "mod_canberra_mtime": $MOD_CANBERRA_MTIME,
    
    "utc_time_enabled": $UTC_TIME_ENABLED,
    "gpredict_cfg_content": "$(escape_json "$GPREDICT_CFG_CONTENT")",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/dsn_multisite_visibility_result.json"
cat /tmp/dsn_multisite_visibility_result.json
echo ""
echo "=== Export Complete ==="