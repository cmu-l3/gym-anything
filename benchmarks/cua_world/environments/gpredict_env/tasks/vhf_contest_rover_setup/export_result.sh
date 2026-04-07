#!/bin/bash
echo "=== Exporting vhf_contest_rover_setup result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Helper function to read a QTH file safely
read_qth() {
    local qth_file=$1
    if [ -f "$qth_file" ]; then
        lat=$(grep -i "^LAT=" "$qth_file" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        lon=$(grep -i "^LON=" "$qth_file" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        alt=$(grep -i "^ALT=" "$qth_file" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        echo "{\"exists\": true, \"lat\": \"$lat\", \"lon\": \"$lon\", \"alt\": \"$alt\"}"
    else
        # Try a case-insensitive match just in case
        local base=$(basename "$qth_file")
        local found="false"
        for f in "${GPREDICT_CONF_DIR}"/*.qth; do
            if echo "$(basename "$f")" | grep -qi "^${base}$"; then
                lat=$(grep -i "^LAT=" "$f" | head -1 | cut -d= -f2 | tr -d '[:space:]')
                lon=$(grep -i "^LON=" "$f" | head -1 | cut -d= -f2 | tr -d '[:space:]')
                alt=$(grep -i "^ALT=" "$f" | head -1 | cut -d= -f2 | tr -d '[:space:]')
                echo "{\"exists\": true, \"lat\": \"$lat\", \"lon\": \"$lon\", \"alt\": \"$alt\"}"
                found="true"
                break
            fi
        done
        if [ "$found" = "false" ]; then
            echo "{\"exists\": false}"
        fi
    fi
}

ROVER_EN82=$(read_qth "${GPREDICT_CONF_DIR}/Rover_EN82.qth")
ROVER_EN81=$(read_qth "${GPREDICT_CONF_DIR}/Rover_EN81.qth")
ROVER_EN91=$(read_qth "${GPREDICT_CONF_DIR}/Rover_EN91.qth")

# Evaluate Module
MOD_EXISTS="false"
MOD_SATELLITES=""
MOD_QTH=""
MOD_LAYOUT=""

CONTEST_ROVER_MOD="${GPREDICT_MOD_DIR}/Contest_Rover.mod"
if [ ! -f "$CONTEST_ROVER_MOD" ]; then
    # Try case insensitive search
    for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
        if echo "$(basename "$mod")" | grep -qi "^contest_rover\.mod$"; then
            CONTEST_ROVER_MOD="$mod"
            break
        fi
    done
fi

if [ -f "$CONTEST_ROVER_MOD" ]; then
    MOD_EXISTS="true"
    MOD_SATELLITES=$(grep -i "^SATELLITES=" "$CONTEST_ROVER_MOD" | head -1 | cut -d= -f2 | tr -d '\n\r')
    MOD_QTH=$(grep -i "^QTHFILE=" "$CONTEST_ROVER_MOD" | head -1 | cut -d= -f2 | tr -d '\n\r')
    MOD_LAYOUT=$(grep -i "^LAYOUT=" "$CONTEST_ROVER_MOD" | head -1 | cut -d= -f2 | tr -d '\n\r')
fi

# Evaluate Auto Update configuration
AUTO_UPDATE="false"
GPREDICT_CFG="${GPREDICT_CONF_DIR}/gpredict.cfg"
if [ -f "$GPREDICT_CFG" ]; then
    # Usually stored under [TLE] section
    AUTO_UPDATE_VAL=$(grep -i "^AUTO_UPDATE=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    if [ "$AUTO_UPDATE_VAL" = "true" ] || [ "$AUTO_UPDATE_VAL" = "1" ]; then
        AUTO_UPDATE="true"
    fi
fi

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

cat > /tmp/vhf_contest_rover_setup_result.json << EOF
{
    "en82": $ROVER_EN82,
    "en81": $ROVER_EN81,
    "en91": $ROVER_EN91,
    "mod_exists": $MOD_EXISTS,
    "mod_satellites": "$(escape_json "$MOD_SATELLITES")",
    "mod_qth": "$(escape_json "$MOD_QTH")",
    "mod_layout": "$(escape_json "$MOD_LAYOUT")",
    "auto_update": $AUTO_UPDATE,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/vhf_contest_rover_setup_result.json"
cat /tmp/vhf_contest_rover_setup_result.json
echo "=== Export Complete ==="