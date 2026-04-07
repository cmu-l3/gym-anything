#!/bin/bash
echo "=== Exporting organize_waveforms_sds result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

# Initialize variables
ARCHIVE_ROOT="/home/ga/Documents/ShadowArchive"
EXPECTED_YEAR="2024"
EXPECTED_NET="GE"

ROOT_EXISTS="false"
HIERARCHY_EXISTS="false"
STATION_COUNT=0
VALID_FILES=0
TOTAL_FILES=0
FILE_CREATED_DURING_TASK="false"

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -d "$ARCHIVE_ROOT" ]; then
    ROOT_EXISTS="true"
    
    # Check if a Year/Network hierarchy structure is there
    if [ -d "$ARCHIVE_ROOT/$EXPECTED_YEAR/$EXPECTED_NET" ]; then
        HIERARCHY_EXISTS="true"
        STATION_COUNT=$(find "$ARCHIVE_ROOT/$EXPECTED_YEAR/$EXPECTED_NET" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l || echo "0")
    fi
    
    # Count valid SDS named files based on our pattern
    VALID_FILES=$(find "$ARCHIVE_ROOT" -name "${EXPECTED_NET}.*.D.${EXPECTED_YEAR}.*" 2>/dev/null | wc -l || echo "0")
    
    # Check modification time to ensure agent generated it during the task (anti-gaming)
    if [ "$VALID_FILES" -gt 0 ]; then
        # Pick one file to check its modification time
        SAMPLE_FILE=$(find "$ARCHIVE_ROOT" -type f | head -1)
        FILE_MTIME=$(stat -c %Y "$SAMPLE_FILE" 2>/dev/null || echo "0")
        
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
            FILE_CREATED_DURING_TASK="true"
        fi
    fi
fi

EXPECTED_COUNT=$(cat /tmp/expected_file_count.txt 2>/dev/null || echo "5")

# Create JSON result in temp, then copy safely
TEMP_JSON=$(mktemp /tmp/organize_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "root_exists": $ROOT_EXISTS,
    "hierarchy_exists": $HIERARCHY_EXISTS,
    "station_count": $STATION_COUNT,
    "valid_files_count": $VALID_FILES,
    "expected_files_count": $EXPECTED_COUNT,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "timestamp": "$(date -Iseconds)"
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