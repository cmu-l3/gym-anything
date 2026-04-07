#!/bin/bash
# Export script for urban_canyon_high_passes task

echo "=== Exporting urban_canyon_high_passes result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Helper function to JSON escape
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

# 1. Check legacy files (Pittsburgh.qth and Amateur.mod)
PITTSBURGH_EXISTS="false"
if [ -f "${GPREDICT_CONF_DIR}/Pittsburgh.qth" ]; then
    PITTSBURGH_EXISTS="true"
fi

AMATEUR_MOD_EXISTS="false"
if [ -f "${GPREDICT_MOD_DIR}/Amateur.mod" ]; then
    AMATEUR_MOD_EXISTS="true"
fi

# 2. Check Manhattan_Urban QTH
MANHATTAN_EXISTS="false"
MANHATTAN_LAT=""
MANHATTAN_LON=""
MANHATTAN_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    
    # Try exact match or proximity to coordinates
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    
    if echo "$basename_qth" | grep -qi "manhattan"; then
        MANHATTAN_EXISTS="true"
        MANHATTAN_LAT="$lat"
        MANHATTAN_LON="$lon"
        MANHATTAN_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

# 3. Check High_Passes.mod
HIGH_PASSES_EXISTS="false"
HIGH_PASSES_SATELLITES=""
HIGH_PASSES_QTHFILE=""
HP_HAS_SO50="false"
HP_HAS_AO73="false"
HP_HAS_AO85="false"
HP_HAS_ISS="false"

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    
    if echo "$modname" | grep -qi "high"; then
        HIGH_PASSES_EXISTS="true"
        HIGH_PASSES_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        HIGH_PASSES_QTHFILE=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r')
        
        if echo "$HIGH_PASSES_SATELLITES" | grep -q "27607"; then HP_HAS_SO50="true"; fi
        if echo "$HIGH_PASSES_SATELLITES" | grep -q "39444"; then HP_HAS_AO73="true"; fi
        if echo "$HIGH_PASSES_SATELLITES" | grep -q "40967"; then HP_HAS_AO85="true"; fi
        if echo "$HIGH_PASSES_SATELLITES" | grep -q "25544"; then HP_HAS_ISS="true"; fi
        break
    fi
done

# 4. Read global preferences (gpredict.cfg)
GPREDICT_CFG_CONTENT=""
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    GPREDICT_CFG_CONTENT=$(cat "${GPREDICT_CONF_DIR}/gpredict.cfg" | tr '\n' '|' | sed 's/"/\\"/g')
fi

# Build JSON Result
cat > /tmp/urban_canyon_high_passes_result.json << EOF
{
    "pittsburgh_exists": $PITTSBURGH_EXISTS,
    "amateur_mod_exists": $AMATEUR_MOD_EXISTS,
    "manhattan_exists": $MANHATTAN_EXISTS,
    "manhattan_lat": "$(escape_json "$MANHATTAN_LAT")",
    "manhattan_lon": "$(escape_json "$MANHATTAN_LON")",
    "manhattan_alt": "$(escape_json "$MANHATTAN_ALT")",
    "high_passes_exists": $HIGH_PASSES_EXISTS,
    "high_passes_satellites": "$(escape_json "$HIGH_PASSES_SATELLITES")",
    "high_passes_qthfile": "$(escape_json "$HIGH_PASSES_QTHFILE")",
    "hp_has_so50": $HP_HAS_SO50,
    "hp_has_ao73": $HP_HAS_AO73,
    "hp_has_ao85": $HP_HAS_AO85,
    "hp_has_iss": $HP_HAS_ISS,
    "gpredict_cfg_content": "$(escape_json "$GPREDICT_CFG_CONTENT")",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/urban_canyon_high_passes_result.json"
cat /tmp/urban_canyon_high_passes_result.json
echo ""
echo "=== Export Complete ==="