#!/bin/bash
echo "=== Exporting import_custom_historical_data result ==="

# Define paths
JSTOCK_DIR="/home/ga/.jstock/1.0.7/UnitedState"
DATABASE_DIR="${JSTOCK_DIR}/database"
WATCHLIST_FILE="${JSTOCK_DIR}/watchlist/My Watchlist/realtimestock.csv"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check Watchlist for TSLA
WATCHLIST_HAS_TSLA="false"
if [ -f "$WATCHLIST_FILE" ]; then
    if grep -q "\"TSLA\"" "$WATCHLIST_FILE"; then
        WATCHLIST_HAS_TSLA="true"
    fi
fi

# 3. Check for Database File (TSLA.zip or TSLA.csv)
HISTORY_FILE_EXISTS="false"
HISTORY_FILE_PATH=""
HISTORY_FILE_MTIME="0"

if [ -f "$DATABASE_DIR/TSLA.zip" ]; then
    HISTORY_FILE_EXISTS="true"
    HISTORY_FILE_PATH="$DATABASE_DIR/TSLA.zip"
    HISTORY_FILE_MTIME=$(stat -c %Y "$HISTORY_FILE_PATH" 2>/dev/null || echo "0")
elif [ -f "$DATABASE_DIR/TSLA.csv" ]; then
    HISTORY_FILE_EXISTS="true"
    HISTORY_FILE_PATH="$DATABASE_DIR/TSLA.csv"
    HISTORY_FILE_MTIME=$(stat -c %Y "$HISTORY_FILE_PATH" 2>/dev/null || echo "0")
fi

# 4. Prepare History File for Verifier
# If it's a zip, unzip it to a temp CSV. If CSV, copy it.
VERIFIER_CSV_PATH="/tmp/tsla_history_extracted.csv"
rm -f "$VERIFIER_CSV_PATH"

if [ "$HISTORY_FILE_EXISTS" = "true" ]; then
    echo "Found history file: $HISTORY_FILE_PATH"
    
    if [[ "$HISTORY_FILE_PATH" == *.zip ]]; then
        # JStock ZIPs usually contain a single CSV or similar format
        unzip -p "$HISTORY_FILE_PATH" > "$VERIFIER_CSV_PATH" 2>/dev/null || true
    else
        cp "$HISTORY_FILE_PATH" "$VERIFIER_CSV_PATH"
    fi
    
    # Ensure readable
    chmod 644 "$VERIFIER_CSV_PATH"
fi

# 5. Check timestamps for anti-gaming
FILE_CREATED_DURING_TASK="false"
if [ "$HISTORY_FILE_MTIME" -gt "$TASK_START" ]; then
    FILE_CREATED_DURING_TASK="true"
fi

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "watchlist_has_tsla": $WATCHLIST_HAS_TSLA,
    "history_file_exists": $HISTORY_FILE_EXISTS,
    "history_file_path": "$HISTORY_FILE_PATH",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "history_extracted_path": "$VERIFIER_CSV_PATH",
    "timestamp": $(date +%s)
}
EOF

# Move JSON to final location
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="