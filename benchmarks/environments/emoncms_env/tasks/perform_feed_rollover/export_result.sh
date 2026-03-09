#!/bin/bash
# Export script for Perform Feed Rollover task
echo "=== Exporting Feed Rollover Result ==="

source /workspace/scripts/task_utils.sh

# Stop the background generator
if [ -f /tmp/generator_pid.txt ]; then
    kill $(cat /tmp/generator_pid.txt) 2>/dev/null || true
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Retrieve Initial State
INITIAL_FEED_ID=$(cat /tmp/initial_feed_id.txt 2>/dev/null || echo "-1")

# 2. Query Current State
# Get ID of feed named 'annual_yield' (The NEW feed)
CURRENT_YIELD_ID=$(db_query "SELECT id FROM feeds WHERE name='annual_yield'" 2>/dev/null | head -1)

# Get ID of feed named 'annual_yield_archive' (The OLD feed)
ARCHIVE_YIELD_ID=$(db_query "SELECT id FROM feeds WHERE name='annual_yield_archive'" 2>/dev/null | head -1)

# Get data points count for both
POINTS_NEW=0
POINTS_ARCHIVE=0
if [ -n "$CURRENT_YIELD_ID" ]; then
    # Usually stored in engine-specific files, but we can assume API or metadata check
    # For PHPFina, difficult to check exact row count via SQL.
    # We will trust the existence and ID check mostly, but try API for value
    # Using fetch to see if data exists
    APIKEY=$(get_apikey_read)
    POINTS_NEW=$(curl -s "${EMONCMS_URL}/feed/data.json?apikey=${APIKEY}&id=${CURRENT_YIELD_ID}&start=$(( $(date +%s) - 3600 ))&end=$(date +%s)&interval=10" | grep -o "," | wc -l)
fi
if [ -n "$ARCHIVE_YIELD_ID" ]; then
     # Check if archive has data (from setup)
     # We inserted 10 points in setup.
     # Just check if ID matches INITIAL_FEED_ID
     :
fi

# 3. Check Input Processing
# We need to see which feed the 'solar_yield' input is currently logging to.
INPUT_ID=$(db_query "SELECT id FROM input WHERE name='solar_yield'" 2>/dev/null | head -1)
PROCESS_LIST=""
if [ -n "$INPUT_ID" ]; then
    PROCESS_LIST=$(db_query "SELECT processList FROM input WHERE id=${INPUT_ID}" 2>/dev/null)
fi

# Process list format in DB is like: "1:25,..." where 1 is process ID (log to feed) and 25 is feed ID
# We want to extract the argument for process 1.
LOGGED_FEED_ID=$(echo "$PROCESS_LIST" | grep -oE '1:[0-9]+' | cut -d':' -f2 || echo "")

# 4. Construct JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_feed_id": $INITIAL_FEED_ID,
    "current_yield_id": ${CURRENT_YIELD_ID:-0},
    "archive_yield_id": ${ARCHIVE_YIELD_ID:-0},
    "logged_feed_id": ${LOGGED_FEED_ID:-0},
    "input_exists": $([ -n "$INPUT_ID" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="