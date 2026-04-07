#!/bin/bash
# Export script for config_audit_cleanup task

echo "=== Exporting config_audit_cleanup task results ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || true

# 1. Check Bogus_Test deletion
BOGUS_EXISTS="false"
if [ -f "${GPREDICT_CONF_DIR}/Bogus_Test.qth" ]; then
    BOGUS_EXISTS="true"
fi

# 2. Check Houston correction
HOUSTON_EXISTS="false"
HOUSTON_LAT=""
HOUSTON_LON=""
HOUSTON_ALT=""
if [ -f "${GPREDICT_CONF_DIR}/Houston.qth" ]; then
    HOUSTON_EXISTS="true"
    HOUSTON_LAT=$(grep -i "^LAT=" "${GPREDICT_CONF_DIR}/Houston.qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    HOUSTON_LON=$(grep -i "^LON=" "${GPREDICT_CONF_DIR}/Houston.qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    HOUSTON_ALT=$(grep -i "^ALT=" "${GPREDICT_CONF_DIR}/Houston.qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
fi

# 3. Check Research.mod cleaning
RESEARCH_EXISTS="false"
RESEARCH_SATS=""
if [ -f "${GPREDICT_MOD_DIR}/Research.mod" ]; then
    RESEARCH_EXISTS="true"
    RESEARCH_SATS=$(grep -i "^SATELLITES=" "${GPREDICT_MOD_DIR}/Research.mod" | head -1 | cut -d= -f2 | tr -d '[:space:]')
fi

# 4. Check Old_Demo deletion
OLD_DEMO_EXISTS="false"
if [ -f "${GPREDICT_MOD_DIR}/Old_Demo.mod" ]; then
    OLD_DEMO_EXISTS="true"
fi

# 5. Check Svalbard addition
SVALBARD_EXISTS="false"
SVALBARD_LAT=""
SVALBARD_LON=""
SVALBARD_ALT=""
# Scan for any QTH that might be svalbard (case-insensitive or slightly different name)
for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    if echo "$basename_qth" | grep -qi "svalbard"; then
        SVALBARD_EXISTS="true"
        SVALBARD_LAT=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        SVALBARD_LON=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        SVALBARD_ALT=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        break
    fi
done

# 6. Check Default QTH
DEFAULT_QTH=""
if [ -f "${GPREDICT_CONF_DIR}/gpredict.cfg" ]; then
    DEFAULT_QTH=$(grep -i "^DEFAULT_QTH=" "${GPREDICT_CONF_DIR}/gpredict.cfg" | head -1 | cut -d= -f2 | tr -d '[:space:]')
fi

# 7. Check Amateur.mod untouched
AMATEUR_EXISTS="false"
if [ -f "${GPREDICT_MOD_DIR}/Amateur.mod" ]; then
    AMATEUR_EXISTS="true"
fi

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "bogus_exists": $BOGUS_EXISTS,
    "houston_exists": $HOUSTON_EXISTS,
    "houston_lat": "$(escape_json "$HOUSTON_LAT")",
    "houston_lon": "$(escape_json "$HOUSTON_LON")",
    "houston_alt": "$(escape_json "$HOUSTON_ALT")",
    "research_exists": $RESEARCH_EXISTS,
    "research_sats": "$(escape_json "$RESEARCH_SATS")",
    "old_demo_exists": $OLD_DEMO_EXISTS,
    "svalbard_exists": $SVALBARD_EXISTS,
    "svalbard_lat": "$(escape_json "$SVALBARD_LAT")",
    "svalbard_lon": "$(escape_json "$SVALBARD_LON")",
    "svalbard_alt": "$(escape_json "$SVALBARD_ALT")",
    "default_qth": "$(escape_json "$DEFAULT_QTH")",
    "amateur_exists": $AMATEUR_EXISTS,
    "task_end_timestamp": "$(date +%s)"
}
EOF

rm -f /tmp/config_audit_cleanup_result.json 2>/dev/null || sudo rm -f /tmp/config_audit_cleanup_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/config_audit_cleanup_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/config_audit_cleanup_result.json
chmod 666 /tmp/config_audit_cleanup_result.json 2>/dev/null || sudo chmod 666 /tmp/config_audit_cleanup_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/config_audit_cleanup_result.json"
cat /tmp/config_audit_cleanup_result.json
echo "=== Export complete ==="