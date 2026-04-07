#!/bin/bash
echo "=== Exporting cubesat_multisite_qth result ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"
GPREDICT_MOD_DIR="${GPREDICT_CONF_DIR}/modules"

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Extract all .qth files into a JSON array
QTHS="["
first=true
for qth in "${GPREDICT_CONF_DIR}"/*.qth; do
    [ -f "$qth" ] || continue
    name=$(basename "$qth")
    lat=$(grep -i "^LAT=" "$qth" | head -1 | cut -d= -f2 | tr -d '\r\n')
    lon=$(grep -i "^LON=" "$qth" | head -1 | cut -d= -f2 | tr -d '\r\n')
    alt=$(grep -i "^ALT=" "$qth" | head -1 | cut -d= -f2 | tr -d '\r\n')
    mtime=$(stat -c %Y "$qth" 2>/dev/null || echo 0)
    
    if [ "$first" = true ]; then first=false; else QTHS="$QTHS,"; fi
    QTHS="$QTHS {\"filename\": \"$name\", \"lat\": \"$lat\", \"lon\": \"$lon\", \"alt\": \"$alt\", \"mtime\": $mtime}"
done
QTHS="$QTHS]"

# Extract all .mod files into a JSON array
MODS="["
first=true
for mod in "${GPREDICT_MOD_DIR}"/*.mod; do
    [ -f "$mod" ] || continue
    name=$(basename "$mod")
    sats=$(grep -i "^SATELLITES=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r\n')
    qthfile=$(grep -i "^QTHFILE=" "$mod" | head -1 | cut -d= -f2 | tr -d '\r\n')
    mtime=$(stat -c %Y "$mod" 2>/dev/null || echo 0)
    
    if [ "$first" = true ]; then first=false; else MODS="$MODS,"; fi
    MODS="$MODS {\"filename\": \"$name\", \"satellites\": \"$sats\", \"qthfile\": \"$qthfile\", \"mtime\": $mtime}"
done
MODS="$MODS]"

# Write final JSON payload
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo 0)

cat > /tmp/cubesat_multisite_result.json << EOF
{
    "qths": $QTHS,
    "mods": $MODS,
    "task_start_time": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/cubesat_multisite_result.json"
cat /tmp/cubesat_multisite_result.json
echo ""
echo "=== Export Complete ==="