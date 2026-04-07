#!/bin/bash
# Export script for hab_telemetry_relay_setup task
# Reads all required configs and exports to JSON

echo "=== Exporting hab_telemetry_relay_setup result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final_screenshot.png 2>/dev/null || true

# --- 1. Check if L_Band_Test.mod was deleted ---
L_BAND_EXISTS="false"
if [ -f "${GPREDICT_MOD_DIR}/L_Band_Test.mod" ]; then
    L_BAND_EXISTS="true"
fi

# --- 2. Find Launch Site QTH (search by Latitude ~34.4) ---
LAUNCH_SITE_EXISTS="false"
LAUNCH_SITE_FILENAME=""
LAUNCH_SITE_LAT=""
LAUNCH_SITE_LON=""
LAUNCH_SITE_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    if [ "$lat_int" = "34" ]; then
        LAUNCH_SITE_EXISTS="true"
        LAUNCH_SITE_FILENAME=$(basename "$qth")
        LAUNCH_SITE_LAT="$lat"
        LAUNCH_SITE_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        LAUNCH_SITE_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

# --- 3. Find Recovery Team QTH (search by Latitude ~35.2) ---
RECOVERY_TEAM_EXISTS="false"
RECOVERY_TEAM_LAT=""
RECOVERY_TEAM_LON=""
RECOVERY_TEAM_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    if [ "$lat_int" = "35" ]; then
        RECOVERY_TEAM_EXISTS="true"
        RECOVERY_TEAM_LAT="$lat"
        RECOVERY_TEAM_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        RECOVERY_TEAM_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

# --- 4. Read HAB_Relays module ---
HAB_MOD_EXISTS="false"
HAB_MOD_NAME=""
HAB_SATELLITES=""
HAB_QTHFILE=""

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "hab\|relay"; then
        HAB_MOD_EXISTS="true"
        HAB_MOD_NAME="$modname"
        HAB_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r')
        HAB_QTHFILE=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r')
        
        # Anti-gaming: Ensure it was created/modified during the task
        MOD_TIME=$(stat -c %Y "$mod" 2>/dev/null || echo "0")
        if [ "$MOD_TIME" -lt "$TASK_START_TIME" ]; then
            HAB_MOD_EXISTS="false" # Consider it invalid if older than task
        fi
        break
    fi
done

# --- 5. Check Imperial units in gpredict.cfg ---
UNIT_VAL="0"
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    UNIT_VAL=$(grep -i "^unit=" "${GPREDICT_CONF_DIR}/gpredict.cfg" | head -1 | cut -d= -f2 | tr -d '[:space:]')
fi

# Escape helper
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/hab_telemetry_result.json << EOF
{
    "l_band_exists": $L_BAND_EXISTS,
    "launch_site_exists": $LAUNCH_SITE_EXISTS,
    "launch_site_filename": "$(escape_json "$LAUNCH_SITE_FILENAME")",
    "launch_site_lat": "$(escape_json "$LAUNCH_SITE_LAT")",
    "launch_site_lon": "$(escape_json "$LAUNCH_SITE_LON")",
    "launch_site_alt": "$(escape_json "$LAUNCH_SITE_ALT")",
    "recovery_team_exists": $RECOVERY_TEAM_EXISTS,
    "recovery_team_lat": "$(escape_json "$RECOVERY_TEAM_LAT")",
    "recovery_team_lon": "$(escape_json "$RECOVERY_TEAM_LON")",
    "recovery_team_alt": "$(escape_json "$RECOVERY_TEAM_ALT")",
    "hab_mod_exists": $HAB_MOD_EXISTS,
    "hab_mod_name": "$(escape_json "$HAB_MOD_NAME")",
    "hab_satellites": "$(escape_json "$HAB_SATELLITES")",
    "hab_qthfile": "$(escape_json "$HAB_QTHFILE")",
    "unit_val": "$(escape_json "$UNIT_VAL")",
    "task_start_time": $TASK_START_TIME,
    "export_timestamp": $(date +%s)
}
EOF

echo "Result saved to /tmp/hab_telemetry_result.json"
cat /tmp/hab_telemetry_result.json
echo ""
echo "=== Export Complete ==="