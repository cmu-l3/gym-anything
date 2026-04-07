#!/bin/bash
# Export script for agency_collaboration_tracking task

echo "=== Exporting agency_collaboration_tracking result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# --- Check Amateur.mod ---
AMATEUR_EXISTS="false"
if [ -f "${GPREDICT_MOD_DIR}/Amateur.mod" ]; then
    AMATEUR_EXISTS="true"
fi

# --- Check NASA_Assets.mod ---
NASA_EXISTS="false"
NASA_SATELLITES=""
for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "nasa"; then
        NASA_EXISTS="true"
        NASA_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r')
        break
    fi
done

# --- Check CNSA_Assets.mod ---
CNSA_EXISTS="false"
CNSA_SATELLITES=""
for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "cnsa"; then
        CNSA_EXISTS="true"
        CNSA_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r')
        break
    fi
done

# --- Scan for Geneva Ground Station (Lat ~46.2, Lon ~6.1) ---
GENEVA_EXISTS="false"
GENEVA_LAT=""
GENEVA_LON=""
GENEVA_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    if [ "$lat_int" = "46" ]; then
        lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        lon_int=$(echo "$lon" | cut -d. -f1 | sed 's/-//')
        if [ "$lon_int" = "6" ]; then
            GENEVA_EXISTS="true"
            GENEVA_LAT="$lat"
            GENEVA_LON="$lon"
            GENEVA_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
            break
        fi
    fi
done

# --- Scan for Beijing Ground Station (Lat ~39.9, Lon ~116.4) ---
BEIJING_EXISTS="false"
BEIJING_LAT=""
BEIJING_LON=""
BEIJING_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    if [ "$lat_int" = "39" ]; then
        lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        lon_int=$(echo "$lon" | cut -d. -f1 | sed 's/-//')
        if [ "$lon_int" = "116" ]; then
            BEIJING_EXISTS="true"
            BEIJING_LAT="$lat"
            BEIJING_LON="$lon"
            BEIJING_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
            break
        fi
    fi
done

# --- Check UTC time setting in gpredict.cfg ---
UTC_TIME_ENABLED="false"
GPREDICT_CFG="${GPREDICT_CONF_DIR}/gpredict.cfg"
GPREDICT_CFG_CONTENT=""
if [ -f "$GPREDICT_CFG" ]; then
    UTC_VAL=$(grep -i "^utc=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    if [ "$UTC_VAL" = "1" ]; then
        UTC_TIME_ENABLED="true"
    fi
    GPREDICT_CFG_CONTENT=$(cat "$GPREDICT_CFG" | tr '\n' '|' | sed 's/"/\\"/g')
fi

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/agency_collaboration_tracking_result.json << EOF
{
    "amateur_exists": $AMATEUR_EXISTS,
    "nasa_exists": $NASA_EXISTS,
    "nasa_satellites": "$(escape_json "$NASA_SATELLITES")",
    "cnsa_exists": $CNSA_EXISTS,
    "cnsa_satellites": "$(escape_json "$CNSA_SATELLITES")",
    "geneva_exists": $GENEVA_EXISTS,
    "geneva_lat": "$(escape_json "$GENEVA_LAT")",
    "geneva_lon": "$(escape_json "$GENEVA_LON")",
    "geneva_alt": "$(escape_json "$GENEVA_ALT")",
    "beijing_exists": $BEIJING_EXISTS,
    "beijing_lat": "$(escape_json "$BEIJING_LAT")",
    "beijing_lon": "$(escape_json "$BEIJING_LON")",
    "beijing_alt": "$(escape_json "$BEIJING_ALT")",
    "utc_time_enabled": $UTC_TIME_ENABLED,
    "gpredict_cfg_content": "$(escape_json "$GPREDICT_CFG_CONTENT")",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/agency_collaboration_tracking_result.json"
cat /tmp/agency_collaboration_tracking_result.json
echo ""
echo "=== Export Complete ==="