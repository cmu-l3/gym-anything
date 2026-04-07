#!/bin/bash
# Export script for ariss_school_contact_setup task

echo "=== Exporting ariss_school_contact_setup result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# --- Helper function to escape strings for JSON ---
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

# --- 1. Find and evaluate Denver_School.qth ---
DENVER_EXISTS="false"
DENVER_LAT=""
DENVER_LON=""
DENVER_ALT=""
DENVER_FILE=""
DENVER_MTIME="0"

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    if echo "$basename_qth" | grep -qi "denver"; then
        DENVER_EXISTS="true"
        DENVER_FILE=$(basename "$qth")
        DENVER_LAT=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        DENVER_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        DENVER_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        DENVER_MTIME=$(stat -c %Y "$qth" 2>/dev/null || echo "0")
        break
    fi
done

# --- 2. Find and evaluate Telebridge_Italy.qth ---
ITALY_EXISTS="false"
ITALY_LAT=""
ITALY_LON=""
ITALY_ALT=""
ITALY_FILE=""
ITALY_MTIME="0"

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    if echo "$basename_qth" | grep -qi "tele\|italy"; then
        ITALY_EXISTS="true"
        ITALY_FILE=$(basename "$qth")
        ITALY_LAT=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        ITALY_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        ITALY_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        ITALY_MTIME=$(stat -c %Y "$qth" 2>/dev/null || echo "0")
        break
    fi
done

# --- 3. Evaluate ARISS_Contact.mod ---
ARISS_EXISTS="false"
ARISS_SATELLITES=""
ARISS_QTHFILE=""
ARISS_MTIME="0"
ARISS_HAS_25544="false"
ARISS_HAS_49044="false"

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "ariss"; then
        ARISS_EXISTS="true"
        ARISS_MTIME=$(stat -c %Y "$mod" 2>/dev/null || echo "0")
        ARISS_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        ARISS_QTHFILE=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r\n')
        if echo "$ARISS_SATELLITES" | grep -q "25544"; then ARISS_HAS_25544="true"; fi
        if echo "$ARISS_SATELLITES" | grep -q "49044"; then ARISS_HAS_49044="true"; fi
        break
    fi
done

# --- 4. Evaluate Other_Passes.mod ---
OTHER_EXISTS="false"
OTHER_SATELLITES=""
OTHER_QTHFILE=""
OTHER_MTIME="0"
OTHER_HAS_7530="false"
OTHER_HAS_27607="false"
OTHER_HAS_39444="false"
OTHER_HAS_40967="false"

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "other\|pass"; then
        OTHER_EXISTS="true"
        OTHER_MTIME=$(stat -c %Y "$mod" 2>/dev/null || echo "0")
        OTHER_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        OTHER_QTHFILE=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r\n')
        # Check for each ID (7530 is often stored as 07530 or 7530)
        if echo "$OTHER_SATELLITES" | grep -qE "7530|07530"; then OTHER_HAS_7530="true"; fi
        if echo "$OTHER_SATELLITES" | grep -q "27607"; then OTHER_HAS_27607="true"; fi
        if echo "$OTHER_SATELLITES" | grep -q "39444"; then OTHER_HAS_39444="true"; fi
        if echo "$OTHER_SATELLITES" | grep -q "40967"; then OTHER_HAS_40967="true"; fi
        break
    fi
done

# --- 5. Check UTC time setting in gpredict.cfg ---
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

# Write results to JSON
cat > /tmp/ariss_school_contact_setup_result.json << EOF
{
    "task_start_time": $TASK_START,
    "denver_exists": $DENVER_EXISTS,
    "denver_file": "$(escape_json "$DENVER_FILE")",
    "denver_lat": "$(escape_json "$DENVER_LAT")",
    "denver_lon": "$(escape_json "$DENVER_LON")",
    "denver_alt": "$(escape_json "$DENVER_ALT")",
    "denver_mtime": $DENVER_MTIME,
    "italy_exists": $ITALY_EXISTS,
    "italy_file": "$(escape_json "$ITALY_FILE")",
    "italy_lat": "$(escape_json "$ITALY_LAT")",
    "italy_lon": "$(escape_json "$ITALY_LON")",
    "italy_alt": "$(escape_json "$ITALY_ALT")",
    "italy_mtime": $ITALY_MTIME,
    "ariss_exists": $ARISS_EXISTS,
    "ariss_satellites": "$(escape_json "$ARISS_SATELLITES")",
    "ariss_qthfile": "$(escape_json "$ARISS_QTHFILE")",
    "ariss_mtime": $ARISS_MTIME,
    "ariss_has_25544": $ARISS_HAS_25544,
    "ariss_has_49044": $ARISS_HAS_49044,
    "other_exists": $OTHER_EXISTS,
    "other_satellites": "$(escape_json "$OTHER_SATELLITES")",
    "other_qthfile": "$(escape_json "$OTHER_QTHFILE")",
    "other_mtime": $OTHER_MTIME,
    "other_has_7530": $OTHER_HAS_7530,
    "other_has_27607": $OTHER_HAS_27607,
    "other_has_39444": $OTHER_HAS_39444,
    "other_has_40967": $OTHER_HAS_40967,
    "utc_time_enabled": $UTC_TIME_ENABLED,
    "gpredict_cfg_content": "$(escape_json "$GPREDICT_CFG_CONTENT")",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/ariss_school_contact_setup_result.json"
cat /tmp/ariss_school_contact_setup_result.json
echo ""
echo "=== Export Complete ==="