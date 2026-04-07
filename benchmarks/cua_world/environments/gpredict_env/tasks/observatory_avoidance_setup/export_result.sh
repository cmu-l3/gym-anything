#!/bin/bash
echo "=== Exporting observatory_avoidance_setup result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || true

# --- Check if OldTracker was deleted ---
OLDTRACKER_EXISTS="false"
if [ -f "${GPREDICT_MOD_DIR}/OldTracker.mod" ]; then
    OLDTRACKER_EXISTS="true"
fi

# --- Check if Amateur.mod was preserved unmodified ---
AMATEUR_PRESERVED="false"
if [ -f "${GPREDICT_MOD_DIR}/Amateur.mod" ]; then
    if diff -q "${GPREDICT_MOD_DIR}/Amateur.mod" /tmp/amateur_mod_backup.txt > /dev/null 2>&1; then
        AMATEUR_PRESERVED="true"
    fi
fi

# --- Extract Lowell QTH data ---
LOWELL_QTH_EXISTS="false"
LOWELL_LAT=""
LOWELL_LON=""
LOWELL_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    if echo "$basename_qth" | grep -qi "lowell\|flagstaff"; then
        LOWELL_QTH_EXISTS="true"
        LOWELL_LAT=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        LOWELL_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        LOWELL_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

# --- Extract McDonald QTH data ---
MCDONALD_QTH_EXISTS="false"
MCDONALD_LAT=""
MCDONALD_LON=""
MCDONALD_ALT=""

for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    if echo "$basename_qth" | grep -qi "mcdonald\|davis"; then
        MCDONALD_QTH_EXISTS="true"
        MCDONALD_LAT=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        MCDONALD_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        MCDONALD_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

# --- Extract Lowell_Avoidance module data ---
LOWELL_MOD_EXISTS="false"
LOWELL_SATELLITES=""
LOWELL_QTHFILE=""

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "lowell"; then
        LOWELL_MOD_EXISTS="true"
        LOWELL_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        LOWELL_QTHFILE=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2)
        break
    fi
done

# --- Extract McDonald_Avoidance module data ---
MCDONALD_MOD_EXISTS="false"
MCDONALD_SATELLITES=""
MCDONALD_QTHFILE=""

for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    modname=$(basename "$mod" .mod)
    if echo "$modname" | grep -qi "mcdonald"; then
        MCDONALD_MOD_EXISTS="true"
        MCDONALD_SATELLITES=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2)
        MCDONALD_QTHFILE=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2)
        break
    fi
done

# --- Extract UTC Preference from gpredict.cfg ---
GPREDICT_CFG_CONTENT=""
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    GPREDICT_CFG_CONTENT=$(cat "${GPREDICT_CONF_DIR}/gpredict.cfg" | tr '\n' '|' | sed 's/"/\\"/g')
fi

# Function to safely escape strings for JSON
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

# Create JSON Result Document
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "oldtracker_exists": $OLDTRACKER_EXISTS,
    "amateur_preserved": $AMATEUR_PRESERVED,
    "lowell_qth_exists": $LOWELL_QTH_EXISTS,
    "lowell_lat": "$(escape_json "$LOWELL_LAT")",
    "lowell_lon": "$(escape_json "$LOWELL_LON")",
    "lowell_alt": "$(escape_json "$LOWELL_ALT")",
    "mcdonald_qth_exists": $MCDONALD_QTH_EXISTS,
    "mcdonald_lat": "$(escape_json "$MCDONALD_LAT")",
    "mcdonald_lon": "$(escape_json "$MCDONALD_LON")",
    "mcdonald_alt": "$(escape_json "$MCDONALD_ALT")",
    "lowell_mod_exists": $LOWELL_MOD_EXISTS,
    "lowell_satellites": "$(escape_json "$LOWELL_SATELLITES")",
    "lowell_qthfile": "$(escape_json "$LOWELL_QTHFILE")",
    "mcdonald_mod_exists": $MCDONALD_MOD_EXISTS,
    "mcdonald_satellites": "$(escape_json "$MCDONALD_SATELLITES")",
    "mcdonald_qthfile": "$(escape_json "$MCDONALD_QTHFILE")",
    "gpredict_cfg_content": "$(escape_json "$GPREDICT_CFG_CONTENT")",
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false")
}
EOF

# Move to final location securely
rm -f /tmp/observatory_avoidance_setup_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/observatory_avoidance_setup_result.json
chmod 666 /tmp/observatory_avoidance_setup_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/observatory_avoidance_setup_result.json"
cat /tmp/observatory_avoidance_setup_result.json
echo "=== Export complete ==="