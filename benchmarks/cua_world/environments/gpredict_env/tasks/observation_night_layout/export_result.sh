#!/bin/bash
echo "=== Exporting observation_night_layout result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Function to parse module data
parse_module() {
    local modfile=$1
    local prefix=$2
    
    if [ -f "$modfile" ]; then
        echo "\"${prefix}_exists\": true,"
        
        # Modification time for anti-gaming
        local mtime=$(stat -c %Y "$modfile")
        echo "\"${prefix}_mtime\": $mtime,"
        
        local satellites=$(grep -i "^SATELLITES=" "$modfile" | head -1 | cut -d= -f2 | tr -d '\r\n')
        echo "\"${prefix}_satellites\": \"$satellites\","
        
        local nviews=$(grep -i "^NVIEWS=" "$modfile" | head -1 | cut -d= -f2 | tr -d '\r\n')
        echo "\"${prefix}_nviews\": \"$nviews\","
        
        # Get all views configured
        local views=$(grep -i "^VIEW_[0-9]=" "$modfile" | cut -d= -f2 | tr '\n' ',' | sed 's/,$//')
        echo "\"${prefix}_views\": \"$views\","
    else
        echo "\"${prefix}_exists\": false,"
    fi
}

# Collect result data
TEMP_JSON=$(mktemp)
echo "{" > "$TEMP_JSON"

# Task start timestamp
START_TS=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
echo "\"task_start_timestamp\": $START_TS," >> "$TEMP_JSON"

# Initial Amateur satellites
INIT_AMATEUR=$(cat /tmp/amateur_initial_sats 2>/dev/null || echo "")
echo "\"initial_amateur_satellites\": \"$INIT_AMATEUR\"," >> "$TEMP_JSON"

# BrightSats.mod
parse_module "${GPREDICT_MOD_DIR}/BrightSats.mod" "brightsats" >> "$TEMP_JSON"

# Amateur.mod
parse_module "${GPREDICT_MOD_DIR}/Amateur.mod" "amateur" >> "$TEMP_JSON"

# Cherry Springs QTH
CHERRY_QTH="${GPREDICT_CONF_DIR}/CherrySprings.qth"
if [ ! -f "$CHERRY_QTH" ]; then
    # Fallback search by coordinates
    for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
        if [ -f "$qth" ]; then
            lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '\r\n')
            if [[ "$lat" == 41.6* ]]; then
                CHERRY_QTH="$qth"
                break
            fi
        fi
    done
fi

if [ -f "$CHERRY_QTH" ]; then
    echo "\"cherry_exists\": true," >> "$TEMP_JSON"
    lat=$(grep -i "^LAT=" "$CHERRY_QTH" | head -1 | cut -d= -f2 | tr -d '\r\n')
    lon=$(grep -i "^LON=" "$CHERRY_QTH" | head -1 | cut -d= -f2 | tr -d '\r\n')
    alt=$(grep -i "^ALT=" "$CHERRY_QTH" | head -1 | cut -d= -f2 | tr -d '\r\n')
    echo "\"cherry_lat\": \"$lat\"," >> "$TEMP_JSON"
    echo "\"cherry_lon\": \"$lon\"," >> "$TEMP_JSON"
    echo "\"cherry_alt\": \"$alt\"," >> "$TEMP_JSON"
else
    echo "\"cherry_exists\": false," >> "$TEMP_JSON"
fi

# UTC configuration
GPREDICT_CFG="${GPREDICT_CONF_DIR}/gpredict.cfg"
if [ -f "$GPREDICT_CFG" ]; then
    utc_val=$(grep -i "^utc=" "$GPREDICT_CFG" | head -1 | cut -d= -f2 | tr -d '\r\n')
    if [ "$utc_val" = "1" ]; then
        echo "\"utc_enabled\": true," >> "$TEMP_JSON"
    else
        echo "\"utc_enabled\": false," >> "$TEMP_JSON"
    fi
else
    echo "\"utc_enabled\": false," >> "$TEMP_JSON"
fi

echo "\"export_timestamp\": $(date +%s)" >> "$TEMP_JSON"
echo "}" >> "$TEMP_JSON"

# Format and save
cat "$TEMP_JSON" > /tmp/observation_night_layout_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/observation_night_layout_result.json"
cat /tmp/observation_night_layout_result.json
echo "=== Export Complete ==="