#!/bin/bash
# Export script for qth_relocation_migration task

echo "=== Exporting qth_relocation_migration result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || true

# Check if Amateur.mod still exists
AMATEUR_MOD_EXISTS="false"
if [ -f "${GPREDICT_MOD_DIR}/Amateur.mod" ]; then
    AMATEUR_MOD_EXISTS="true"
fi

# Scan for Denver ground station by latitude ~39.7 / longitude ~-104.9
DENVER_QTH_EXISTS="false"
DENVER_QTH_FILE=""
DENVER_LAT=""
DENVER_LON=""
DENVER_ALT=""
DENVER_WX=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    if [ "$lat_int" = "39" ]; then
        lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        lon_abs=$(echo "$lon" | sed 's/-//')
        lon_int=$(echo "$lon_abs" | cut -d. -f1)
        if [ "$lon_int" = "104" ]; then
            DENVER_QTH_EXISTS="true"
            DENVER_QTH_FILE=$(basename "$qth")
            DENVER_LAT="$lat"
            DENVER_LON="$lon"
            DENVER_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
            DENVER_WX=$(grep -i "^WX=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
            break
        fi
    fi
done

# Scan for DenverAmateur.mod
DENVER_AMATEUR_EXISTS="false"
DENVER_AMATEUR_SATELLITES=""
for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "denver.*amateur\|amateur.*denver"; then
        DENVER_AMATEUR_EXISTS="true"
        DENVER_AMATEUR_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        break
    fi
done

# Scan for DenverWX.mod
DENVER_WX_EXISTS="false"
DENVER_WX_SATELLITES=""
for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "denver.*wx\|denver.*weather\|wx.*denver"; then
        DENVER_WX_EXISTS="true"
        DENVER_WX_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        break
    fi
done

# Get gpredict.cfg contents
GPREDICT_CFG_CONTENT=""
UTC_TIME_ENABLED="false"
DEFAULT_QTH=""

if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    GPREDICT_CFG_CONTENT=$(cat "${GPREDICT_CONF_DIR}/gpredict.cfg" | tr '\n' '|' | sed 's/"/\\"/g')
    
    DEFAULT_QTH=$(grep -i "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    
    UTC_VAL=$(grep -i "^utc=" "${GPREDICT_CONF_DIR}/gpredict.cfg" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    if [ "$UTC_VAL" = "1" ]; then
        UTC_TIME_ENABLED="true"
    fi
fi

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/qth_relocation_result.json << EOF
{
    "amateur_mod_exists": $AMATEUR_MOD_EXISTS,
    "denver_qth_exists": $DENVER_QTH_EXISTS,
    "denver_qth_file": "$(escape_json "$DENVER_QTH_FILE")",
    "denver_lat": "$(escape_json "$DENVER_LAT")",
    "denver_lon": "$(escape_json "$DENVER_LON")",
    "denver_alt": "$(escape_json "$DENVER_ALT")",
    "denver_wx": "$(escape_json "$DENVER_WX")",
    "denver_amateur_exists": $DENVER_AMATEUR_EXISTS,
    "denver_amateur_satellites": "$(escape_json "$DENVER_AMATEUR_SATELLITES")",
    "denver_wx_exists": $DENVER_WX_EXISTS,
    "denver_wx_satellites": "$(escape_json "$DENVER_WX_SATELLITES")",
    "gpredict_cfg_content": "$(escape_json "$GPREDICT_CFG_CONTENT")",
    "default_qth": "$(escape_json "$DEFAULT_QTH")",
    "utc_time_enabled": $UTC_TIME_ENABLED,
    "task_start_timestamp": "$(cat /tmp/task_start_time.txt 2>/dev/null || echo 0)",
    "export_timestamp": "$(date +%s)"
}
EOF

chmod 644 /tmp/qth_relocation_result.json
echo "Result JSON saved to /tmp/qth_relocation_result.json"
cat /tmp/qth_relocation_result.json
echo "=== Export Complete ==="