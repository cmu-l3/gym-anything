#!/bin/bash
echo "=== Exporting import_watchlist_from_csv task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
WATCHLIST_BASE="/home/ga/.jstock/1.0.7/UnitedState/watchlist"

# ============================================================
# Step 1: Gracefully close JStock to force state save
# ============================================================
echo "--- Closing JStock to force state save ---"
if pgrep -f "jstock" > /dev/null 2>&1; then
    # Try Alt+F4
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key alt+F4" 2>/dev/null || true
    sleep 3
    # Confirm 'Do you want to save?' dialog if it appears (Enter)
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
    sleep 5
    # Force kill if still running
    pkill -f "jstock" 2>/dev/null || true
    sleep 2
fi

# Take final screenshot (after close, or just desktop if closed)
# Ideally we wanted one BEFORE close, but framework captures screenshots during trajectory.
# This screenshot confirms app is closed or final state.
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# ============================================================
# Step 2: Analyze Watchlist Files
# ============================================================

# Target stocks to look for
TARGETS=("JNJ" "PFE" "UNH" "ABT" "TMO" "ABBV" "MRK" "LLY")
FOUND_STOCKS=()
FILES_MODIFIED_DURING_TASK=0
WATCHLIST_FILES_FOUND=0

# Scan all CSV files in the watchlist directory
if [ -d "$WATCHLIST_BASE" ]; then
    while IFS= read -r csv_file; do
        echo "Checking file: $csv_file"
        WATCHLIST_FILES_FOUND=$((WATCHLIST_FILES_FOUND + 1))
        
        # Check modification time
        FILE_MTIME=$(stat -c %Y "$csv_file" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
            FILES_MODIFIED_DURING_TASK=$((FILES_MODIFIED_DURING_TASK + 1))
        fi

        # Check content for stocks
        FILE_CONTENT=$(cat "$csv_file" 2>/dev/null)
        for stock in "${TARGETS[@]}"; do
            # Look for "STOCK" (quoted) to avoid partial matches
            if echo "$FILE_CONTENT" | grep -qi "\"${stock}\""; then
                # Add to found list if not already there
                if [[ ! " ${FOUND_STOCKS[@]} " =~ " ${stock} " ]]; then
                    FOUND_STOCKS+=("$stock")
                fi
            fi
        done
    done < <(find "$WATCHLIST_BASE" -name "*.csv" -type f)
fi

# Convert array to JSON array string
JSON_FOUND_STOCKS=$(printf '%s\n' "${FOUND_STOCKS[@]}" | jq -R . | jq -s .)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "watchlist_files_scanned": $WATCHLIST_FILES_FOUND,
    "files_modified_during_task": $FILES_MODIFIED_DURING_TASK,
    "found_stocks": $JSON_FOUND_STOCKS,
    "target_count": 8,
    "found_count": ${#FOUND_STOCKS[@]},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="