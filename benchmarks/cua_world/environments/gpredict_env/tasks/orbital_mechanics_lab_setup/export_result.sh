#!/bin/bash
echo "=== Exporting orbital_mechanics_lab_setup result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || true

# 1. Check Amateur.mod deletion
AMATEUR_DELETED="true"
if [ -f "${GPREDICT_MOD_DIR}/Amateur.mod" ]; then
    AMATEUR_DELETED="false"
fi

# 2. Check Crewed_Stations.mod
CS_EXISTS="false"
CS_SATS=""
for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "crewed"; then
        CS_EXISTS="true"
        CS_SATS=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        break
    fi
done

# 3. Check Polar_Weather.mod
PW_EXISTS="false"
PW_SATS=""
for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "polar\|weather"; then
        PW_EXISTS="true"
        PW_SATS=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        break
    fi
done

# 4. Check MIT ground station
MIT_EXISTS="false"
MIT_LAT=""
MIT_LON=""
MIT_ALT=""
for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    if [ "$lat_int" = "42" ]; then
        lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        lon_int=$(echo "$lon" | sed 's/-//' | cut -d. -f1)
        if [ "$lon_int" = "71" ]; then
            MIT_EXISTS="true"
            MIT_LAT="$lat"
            MIT_LON="$lon"
            MIT_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
            break
        fi
    fi
done

# 5 & 6. Check preferences in gpredict.cfg
GPREDICT_CFG_CONTENT=""
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    GPREDICT_CFG_CONTENT=$(cat "${GPREDICT_CONF_DIR}/gpredict.cfg" | tr '\n' '|' | sed 's/"/\\"/g')
fi

# Escape JSON strings
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/orbital_mechanics_lab_result.json << EOF
{
    "amateur_deleted": $AMATEUR_DELETED,
    "cs_exists": $CS_EXISTS,
    "cs_sats": "$(escape_json "$CS_SATS")",
    "pw_exists": $PW_EXISTS,
    "pw_sats": "$(escape_json "$PW_SATS")",
    "mit_exists": $MIT_EXISTS,
    "mit_lat": "$(escape_json "$MIT_LAT")",
    "mit_lon": "$(escape_json "$MIT_LON")",
    "mit_alt": "$(escape_json "$MIT_ALT")",
    "gpredict_cfg_content": "$(escape_json "$GPREDICT_CFG_CONTENT")"
}
EOF

# Use safe permission assignment
chmod 666 /tmp/orbital_mechanics_lab_result.json 2>/dev/null || sudo chmod 666 /tmp/orbital_mechanics_lab_result.json 2>/dev/null || true

echo "Result saved to /tmp/orbital_mechanics_lab_result.json"