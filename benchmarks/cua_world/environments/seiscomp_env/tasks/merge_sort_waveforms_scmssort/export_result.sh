#!/bin/bash
echo "=== Exporting merge_sort_waveforms_scmssort results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

MERGED="/home/ga/merged_waveforms.mseed"
INVENTORY="/home/ga/waveform_inventory.txt"
EXPECTED_STATIONS=$(cat /tmp/expected_stations.txt 2>/dev/null || echo "")

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- Check Merged File ---
MERGED_EXISTS="false"
MERGED_SIZE=0
MERGED_CREATED_DURING_TASK="false"
MERGED_IS_MINISEED="false"
MERGED_STATIONS_COUNT=0

if [ -f "$MERGED" ]; then
    MERGED_EXISTS="true"
    MERGED_SIZE=$(stat -c%s "$MERGED" 2>/dev/null || echo "0")
    
    MERGED_MTIME=$(stat -c%Y "$MERGED" 2>/dev/null || echo "0")
    if [ "$MERGED_MTIME" -gt "$TASK_START" ]; then
        MERGED_CREATED_DURING_TASK="true"
    fi
    
    # Check if file contains recognizable miniSEED content by looking for network string "GE"
    if strings "$MERGED" 2>/dev/null | head -100 | grep -q "GE"; then
        MERGED_IS_MINISEED="true"
    fi
    
    # Count unique stations in the merged file
    MERGED_STATIONS_COUNT=$(strings "$MERGED" 2>/dev/null | grep -oE '(TOLI|GSI|KWP|SANI|BKB)' | sort -u | wc -l || echo "0")
fi

# --- Check Inventory File ---
INVENTORY_EXISTS="false"
INVENTORY_SIZE=0
INVENTORY_LINES=0
INVENTORY_CREATED_DURING_TASK="false"
INVENTORY_HAS_GE="false"
INVENTORY_STATIONS_COUNT=0

if [ -f "$INVENTORY" ]; then
    INVENTORY_EXISTS="true"
    INVENTORY_SIZE=$(stat -c%s "$INVENTORY" 2>/dev/null || echo "0")
    INVENTORY_LINES=$(wc -l < "$INVENTORY" 2>/dev/null || echo "0")
    
    INVENTORY_MTIME=$(stat -c%Y "$INVENTORY" 2>/dev/null || echo "0")
    if [ "$INVENTORY_MTIME" -gt "$TASK_START" ]; then
        INVENTORY_CREATED_DURING_TASK="true"
    fi
    
    if grep -qi "GE" "$INVENTORY"; then
        INVENTORY_HAS_GE="true"
    fi
    
    # Check which expected stations appear in the inventory
    for STA in $EXPECTED_STATIONS; do
        if grep -qi "$STA" "$INVENTORY"; then
            INVENTORY_STATIONS_COUNT=$((INVENTORY_STATIONS_COUNT + 1))
        fi
    done
fi

# Check for terminal running
TERMINAL_RUNNING=$(pgrep -f "xterm" > /dev/null && echo "true" || echo "false")

# Create JSON result safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "terminal_was_running": $TERMINAL_RUNNING,
    "merged_file": {
        "exists": $MERGED_EXISTS,
        "size_bytes": $MERGED_SIZE,
        "created_during_task": $MERGED_CREATED_DURING_TASK,
        "is_miniseed": $MERGED_IS_MINISEED,
        "stations_count": $MERGED_STATIONS_COUNT
    },
    "inventory_file": {
        "exists": $INVENTORY_EXISTS,
        "size_bytes": $INVENTORY_SIZE,
        "lines": $INVENTORY_LINES,
        "created_during_task": $INVENTORY_CREATED_DURING_TASK,
        "has_ge_network": $INVENTORY_HAS_GE,
        "stations_count": $INVENTORY_STATIONS_COUNT
    }
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="