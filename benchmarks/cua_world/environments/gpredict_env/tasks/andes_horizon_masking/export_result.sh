#!/bin/bash
# Export script for andes_horizon_masking task

echo "=== Exporting andes_horizon_masking result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Initialize variables
SANTIAGO_QTH_EXISTS="false"
SANTIAGO_QTH_CONTENT=""
ANDES_MOD_EXISTS="false"
ANDES_MOD_CONTENT=""

# Find Santiago QTH file (checking around Lat ~ -33.45)
for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    basename_qth=$(basename "$qth" .qth)
    
    # Check if this is the target QTH by name or by coordinates
    is_target=false
    if echo "$basename_qth" | grep -qi "santiago"; then
        is_target=true
    else
        lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
        lat_int=$(echo "$lat" | cut -d. -f1)
        # Santiago is ~ -33
        if [ "$lat_int" = "-33" ] || [ "$lat_int" = "-34" ]; then
            is_target=true
        fi
    fi
    
    if [ "$is_target" = true ]; then
        SANTIAGO_QTH_EXISTS="true"
        SANTIAGO_QTH_CONTENT=$(cat "$qth" | tr '\n' '|' | sed 's/"/\\"/g')
        break
    fi
done

# Find Andes_EO module file
for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    basename_mod=$(basename "$mod" .mod)
    
    if echo "$basename_mod" | grep -qi "andes"; then
        ANDES_MOD_EXISTS="true"
        ANDES_MOD_CONTENT=$(cat "$mod" | tr '\n' '|' | sed 's/"/\\"/g')
        break
    fi
done

escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

# Create JSON Result
cat > /tmp/andes_horizon_masking_result.json << EOF
{
    "santiago_qth_exists": $SANTIAGO_QTH_EXISTS,
    "santiago_qth_content": "$(escape_json "$SANTIAGO_QTH_CONTENT")",
    "andes_mod_exists": $ANDES_MOD_EXISTS,
    "andes_mod_content": "$(escape_json "$ANDES_MOD_CONTENT")",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/andes_horizon_masking_result.json"
cat /tmp/andes_horizon_masking_result.json
echo ""
echo "=== Export Complete ==="