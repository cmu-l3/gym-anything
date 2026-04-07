#!/bin/bash
# Export script for noaa_apt_reception_setup task

echo "=== Exporting task results ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"
GPREDICT_TRSP_DIR="${GPREDICT_CONF_DIR}/trsp"

# Record task end time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || true

# Check if application was running
APP_RUNNING=$(pgrep -x "gpredict" > /dev/null && echo "true" || echo "false")

# Preserve check
AMATEUR_EXISTS="false"
if [ -f "${GPREDICT_MOD_DIR}/Amateur.mod" ]; then
    AMATEUR_EXISTS="true"
fi
PITTSBURGH_EXISTS="false"
if [ -f "${GPREDICT_CONF_DIR}/Pittsburgh.qth" ]; then
    PITTSBURGH_EXISTS="true"
fi

# --- Read NOAA_APT.mod ---
NOAA_MOD_EXISTS="false"
NOAA_SATELLITES=""
NOAA_TRACK_NUM="1"
NOAA_MTIME="0"

# Search for NOAA_APT module
NOAA_MOD="${GPREDICT_MOD_DIR}/NOAA_APT.mod"
if [ ! -f "$NOAA_MOD" ]; then
    NOAA_MOD="${GPREDICT_MOD_DIR}/noaa_apt.mod"
fi

if [ -f "$NOAA_MOD" ]; then
    NOAA_MOD_EXISTS="true"
    NOAA_MTIME=$(stat -c %Y "$NOAA_MOD" 2>/dev/null || echo "0")
    NOAA_SATELLITES=$(grep -i "^SATELLITES=" "$NOAA_MOD" | head -1 | cut -d= -f2 | tr -d '\r')
    NOAA_TRACK_NUM=$(grep -i "TRACK.*NUM=" "$NOAA_MOD" | head -1 | cut -d= -f2 | tr -d '\r')
    if [ -z "$NOAA_TRACK_NUM" ]; then
        NOAA_TRACK_NUM=$(grep -i "NUM.*TRACKS=" "$NOAA_MOD" | head -1 | cut -d= -f2 | tr -d '\r')
    fi
else
    # Fallback search by contents
    for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
        [ -f "$mod" ] || continue
        if grep -qi "25338" "$mod" && grep -qi "28654" "$mod"; then
            if ! echo "$mod" | grep -qi "amateur"; then
                NOAA_MOD_EXISTS="true"
                NOAA_MTIME=$(stat -c %Y "$mod" 2>/dev/null || echo "0")
                NOAA_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r')
                NOAA_TRACK_NUM=$(grep -i "TRACK.*NUM=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r')
                break
            fi
        fi
    done
fi
[ -z "$NOAA_TRACK_NUM" ] && NOAA_TRACK_NUM="1"

# --- Read Wallops QTH ---
WALLOPS_EXISTS="false"
WALLOPS_LAT=""
WALLOPS_LON=""
WALLOPS_ALT=""
WALLOPS_MTIME="0"

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    if echo "$basename_qth" | grep -qi "pittsburgh"; then continue; fi

    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lat_int=$(echo "$lat" | cut -d. -f1)
    
    if echo "$basename_qth" | grep -qi "wallops" || [ "$lat_int" = "37" ]; then
        WALLOPS_EXISTS="true"
        WALLOPS_LAT="$lat"
        WALLOPS_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        WALLOPS_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        WALLOPS_MTIME=$(stat -c %Y "$qth" 2>/dev/null || echo "0")
        break
    fi
done

# --- Read Transponder Files ---
read_trsp() {
    local id=$1
    local f="${GPREDICT_TRSP_DIR}/${id}.trsp"
    if [ -f "$f" ]; then
        local down=$(grep -i "^DOWN_LOW=" "$f" | head -1 | cut -d= -f2 | tr -d '\r')
        local mode=$(grep -i "^MODE=" "$f" | head -1 | cut -d= -f2 | tr -d '\r')
        local mtime=$(stat -c %Y "$f" 2>/dev/null || echo "0")
        echo "true|${down}|${mode}|${mtime}"
    else
        echo "false|||0"
    fi
}

TRSP_15=$(read_trsp 25338)
TRSP_18=$(read_trsp 28654)
TRSP_19=$(read_trsp 33591)

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "amateur_preserved": $AMATEUR_EXISTS,
    "pittsburgh_preserved": $PITTSBURGH_EXISTS,
    "noaa_mod_exists": $NOAA_MOD_EXISTS,
    "noaa_mod_mtime": $NOAA_MTIME,
    "noaa_satellites": "$(escape_json "$NOAA_SATELLITES")",
    "noaa_track_num": "$(escape_json "$NOAA_TRACK_NUM")",
    "wallops_exists": $WALLOPS_EXISTS,
    "wallops_lat": "$(escape_json "$WALLOPS_LAT")",
    "wallops_lon": "$(escape_json "$WALLOPS_LON")",
    "wallops_alt": "$(escape_json "$WALLOPS_ALT")",
    "wallops_mtime": $WALLOPS_MTIME,
    "trsp_15_exists": $(echo "$TRSP_15" | cut -d\| -f1),
    "trsp_15_down": "$(escape_json "$(echo "$TRSP_15" | cut -d\| -f2)")",
    "trsp_15_mode": "$(escape_json "$(echo "$TRSP_15" | cut -d\| -f3)")",
    "trsp_15_mtime": $(echo "$TRSP_15" | cut -d\| -f4),
    "trsp_18_exists": $(echo "$TRSP_18" | cut -d\| -f1),
    "trsp_18_down": "$(escape_json "$(echo "$TRSP_18" | cut -d\| -f2)")",
    "trsp_18_mode": "$(escape_json "$(echo "$TRSP_18" | cut -d\| -f3)")",
    "trsp_18_mtime": $(echo "$TRSP_18" | cut -d\| -f4),
    "trsp_19_exists": $(echo "$TRSP_19" | cut -d\| -f1),
    "trsp_19_down": "$(escape_json "$(echo "$TRSP_19" | cut -d\| -f2)")",
    "trsp_19_mode": "$(escape_json "$(echo "$TRSP_19" | cut -d\| -f3)")",
    "trsp_19_mtime": $(echo "$TRSP_19" | cut -d\| -f4),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="