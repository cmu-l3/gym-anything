#!/bin/bash
# Export script for remote_island_dxpedition task

echo "=== Exporting remote_island_dxpedition result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# --- Initialize JSON blocks ---
SABLE_JSON='{"exists": false}'
HALIFAX_JSON='{"exists": false}'

# --- Search for QTH files by latitude approximation ---
for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    bname=$(basename "$qth")
    
    # Skip standard default
    if echo "$bname" | grep -qi "pittsburgh"; then continue; fi

    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    alt=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '[:space:]')
    mtime=$(stat -c %Y "$qth" 2>/dev/null || echo "0")

    lat_int=$(echo "$lat" | cut -d. -f1)
    
    # Sable Island Lat is ~43.9
    if [ "$lat_int" = "43" ]; then
        SABLE_JSON="{\"exists\": true, \"filename\": \"$bname\", \"lat\": \"$lat\", \"lon\": \"$lon\", \"alt\": \"$alt\", \"mtime\": $mtime}"
    # Halifax Lat is ~44.6
    elif [ "$lat_int" = "44" ]; then
        HALIFAX_JSON="{\"exists\": true, \"filename\": \"$bname\", \"lat\": \"$lat\", \"lon\": \"$lon\", \"alt\": \"$alt\", \"mtime\": $mtime}"
    fi
done

# --- Search for DXpedition module ---
DX_JSON='{"exists": false}'
for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    bname=$(basename "$mod")
    
    # Must not be the amateur module
    if echo "$bname" | grep -qi "amateur"; then continue; fi
    
    # Look for module containing "DX"
    if echo "$bname" | grep -qi "dx"; then
        # Use base64 to safely embed the full module configuration in JSON
        content_b64=$(cat "$mod" | base64 -w 0)
        mtime=$(stat -c %Y "$mod" 2>/dev/null || echo "0")
        DX_JSON="{\"exists\": true, \"filename\": \"$bname\", \"content_b64\": \"$content_b64\", \"mtime\": $mtime}"
        break
    fi
done

# --- Check if Amateur module was deleted ---
AMATEUR_EXISTS="false"
if [ -f "${GPREDICT_MOD_DIR}/Amateur.mod" ]; then
    AMATEUR_EXISTS="true"
fi

# --- Write output JSON ---
cat > /tmp/remote_island_dxpedition_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "sable_qth": $SABLE_JSON,
    "halifax_qth": $HALIFAX_JSON,
    "dx_mod": $DX_JSON,
    "amateur_mod_exists": $AMATEUR_EXISTS,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/remote_island_dxpedition_result.json"
cat /tmp/remote_island_dxpedition_result.json
echo ""
echo "=== Export Complete ==="