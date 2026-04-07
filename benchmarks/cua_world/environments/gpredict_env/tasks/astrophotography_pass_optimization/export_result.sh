#!/bin/bash
# Export script for astrophotography_pass_optimization task
# Extracts configuration files safely using Base64 encoding to prevent JSON parsing errors.

echo "=== Exporting astrophotography_pass_optimization result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || true

# Find MaunaKea QTH (case-insensitive filename match)
MAUNA_QTH_PATH=""
for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    if echo "$(basename "$qth")" | grep -qi "mauna"; then
        MAUNA_QTH_PATH="$qth"
        break
    fi
done

# Find Astro_Targets mod (case-insensitive filename match)
ASTRO_MOD_PATH=""
for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    if echo "$(basename "$mod")" | grep -qi "astro"; then
        ASTRO_MOD_PATH="$mod"
        break
    fi
done

# Base64 encode configurations so the Python verifier can safely decode and parse them
CFG_B64=$(base64 -w 0 "${GPREDICT_CONF_DIR}/gpredict.cfg" 2>/dev/null || echo "")
QTH_B64=""
MOD_B64=""

if [ -n "$MAUNA_QTH_PATH" ] && [ -f "$MAUNA_QTH_PATH" ]; then
    QTH_B64=$(base64 -w 0 "$MAUNA_QTH_PATH" 2>/dev/null || echo "")
fi

if [ -n "$ASTRO_MOD_PATH" ] && [ -f "$ASTRO_MOD_PATH" ]; then
    MOD_B64=$(base64 -w 0 "$ASTRO_MOD_PATH" 2>/dev/null || echo "")
fi

# Determine QTH filename if found
QTH_FILENAME=""
if [ -n "$MAUNA_QTH_PATH" ]; then
    QTH_FILENAME=$(basename "$MAUNA_QTH_PATH")
fi

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

cat > /tmp/astrophotography_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "qth_filename": "$QTH_FILENAME",
    "maunakea_qth_b64": "$QTH_B64",
    "astro_mod_b64": "$MOD_B64",
    "gpredict_cfg_b64": "$CFG_B64",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/astrophotography_result.json"
echo "=== Export Complete ==="