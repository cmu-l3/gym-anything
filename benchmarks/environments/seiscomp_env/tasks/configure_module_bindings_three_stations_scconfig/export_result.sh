#!/bin/bash
echo "=== Exporting configure_module_bindings_three_stations_scconfig result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
TASK="configure_module_bindings_three_stations_scconfig"
BINDINGS_DIR="$SEISCOMP_ROOT/etc/key"
STATIONS="GSI BKB SANI"

TASK_START=$(cat /tmp/${TASK}_start_ts 2>/dev/null || echo "0")
INITIAL_SCAUTOPICK=$(cat /tmp/${TASK}_initial_scautopick_count 2>/dev/null || echo "0")
INITIAL_SCAMP=$(cat /tmp/${TASK}_initial_scamp_count 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK}_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK}_end_screenshot.png 2>/dev/null || true

# Check each station's key file for module bindings
GSI_SCAUTOPICK=false
GSI_SCAMP=false
BKB_SCAUTOPICK=false
BKB_SCAMP=false
SANI_SCAUTOPICK=false
SANI_SCAMP=false

GSI_KEY="$BINDINGS_DIR/station_GE_GSI"
BKB_KEY="$BINDINGS_DIR/station_GE_BKB"
SANI_KEY="$BINDINGS_DIR/station_GE_SANI"

# Check GE.GSI
if [ -f "$GSI_KEY" ]; then
    grep -q "^scautopick" "$GSI_KEY" 2>/dev/null && GSI_SCAUTOPICK=true
    grep -q "^scamp" "$GSI_KEY" 2>/dev/null && GSI_SCAMP=true
    echo "GE.GSI key file contents:"
    cat "$GSI_KEY" 2>/dev/null | head -20
fi

# Check GE.BKB
if [ -f "$BKB_KEY" ]; then
    grep -q "^scautopick" "$BKB_KEY" 2>/dev/null && BKB_SCAUTOPICK=true
    grep -q "^scamp" "$BKB_KEY" 2>/dev/null && BKB_SCAMP=true
    echo "GE.BKB key file contents:"
    cat "$BKB_KEY" 2>/dev/null | head -20
fi

# Check GE.SANI
if [ -f "$SANI_KEY" ]; then
    grep -q "^scautopick" "$SANI_KEY" 2>/dev/null && SANI_SCAUTOPICK=true
    grep -q "^scamp" "$SANI_KEY" 2>/dev/null && SANI_SCAMP=true
    echo "GE.SANI key file contents:"
    cat "$SANI_KEY" 2>/dev/null | head -20
fi

# Count how many stations have each module
SCAUTOPICK_STATIONS=0
SCAMP_STATIONS=0
for STA in $STATIONS; do
    KEY_FILE="$BINDINGS_DIR/station_GE_${STA}"
    if [ -f "$KEY_FILE" ] && grep -q "^scautopick" "$KEY_FILE" 2>/dev/null; then
        SCAUTOPICK_STATIONS=$((SCAUTOPICK_STATIONS + 1))
    fi
    if [ -f "$KEY_FILE" ] && grep -q "^scamp" "$KEY_FILE" 2>/dev/null; then
        SCAMP_STATIONS=$((SCAMP_STATIONS + 1))
    fi
done

echo "Stations with scautopick binding: $SCAUTOPICK_STATIONS / 3"
echo "Stations with scamp binding: $SCAMP_STATIONS / 3"

# Check if key files were modified after task start
GSI_IS_NEW=false
BKB_IS_NEW=false
SANI_IS_NEW=false

for STA in GSI BKB SANI; do
    KEY_FILE="$BINDINGS_DIR/station_GE_${STA}"
    if [ -f "$KEY_FILE" ]; then
        MTIME=$(stat -c %Y "$KEY_FILE" 2>/dev/null || echo "0")
        if [ "$MTIME" -gt "$TASK_START" ]; then
            eval "${STA}_IS_NEW=true"
        fi
    fi
done

cat > /tmp/${TASK}_result.json << EOF
{
    "task": "$TASK",
    "task_start": $TASK_START,
    "initial_scautopick_count": $INITIAL_SCAUTOPICK,
    "initial_scamp_count": $INITIAL_SCAMP,
    "gsi_has_scautopick": $GSI_SCAUTOPICK,
    "gsi_has_scamp": $GSI_SCAMP,
    "bkb_has_scautopick": $BKB_SCAUTOPICK,
    "bkb_has_scamp": $BKB_SCAMP,
    "sani_has_scautopick": $SANI_SCAUTOPICK,
    "sani_has_scamp": $SANI_SCAMP,
    "scautopick_station_count": $SCAUTOPICK_STATIONS,
    "scamp_station_count": $SCAMP_STATIONS,
    "gsi_key_is_new": $GSI_IS_NEW,
    "bkb_key_is_new": $BKB_IS_NEW,
    "sani_key_is_new": $SANI_IS_NEW
}
EOF

echo "Result written to /tmp/${TASK}_result.json"
cat /tmp/${TASK}_result.json
echo "=== Export complete ==="
