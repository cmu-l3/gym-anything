#!/system/bin/sh
# Export script for download_sectional_chart task
# Runs inside the Android environment

echo "=== Exporting download_sectional_chart results ==="

DATA_DIR="/sdcard/com.ds.avare"
RESULT_FILE="/sdcard/task_result.json"

# 1. Capture final state screenshot
screencap -p /sdcard/task_final.png

# 2. Calculate file system changes
START_TIME=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /sdcard/initial_file_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(find "$DATA_DIR" -type f 2>/dev/null | wc -l)

# Count new files created AFTER task start
# 'find -newer' might not be available in minimal Android shell, so we iterate or rely on count diff
# We will use simple count difference and 'ls -l' inspection for the verifier
NEW_FILES_COUNT=$((CURRENT_COUNT - INITIAL_COUNT))

# Calculate total size of San Francisco related files
# Look for files containing "SanFrancisco" or created recently
# Since `stat` or complex `find` might be limited, we'll try a du specific to the expected file pattern
SF_SIZE_BYTES=0
SF_FILES_EXIST="false"

# Check if specific San Francisco files exist
if ls "$DATA_DIR"/*SanFrancisco* >/dev/null 2>&1; then
    SF_FILES_EXIST="true"
    # Estimate size
    SF_SIZE_BYTES=$(du -k "$DATA_DIR"/*SanFrancisco* 2>/dev/null | awk '{sum+=$1} END {print sum*1024}')
fi

# Also check tiles directory if applicable
if [ -d "$DATA_DIR/tiles/sectional" ]; then
   TILES_SIZE=$(du -k "$DATA_DIR/tiles/sectional" 2>/dev/null | awk '{sum+=$1} END {print sum*1024}')
   SF_SIZE_BYTES=$((SF_SIZE_BYTES + TILES_SIZE))
fi

echo "New files count: $NEW_FILES_COUNT"
echo "San Francisco data size: $SF_SIZE_BYTES bytes"

# 3. Create JSON result
# Note: JSON creation manually to avoid dependencies
echo "{" > "$RESULT_FILE"
echo "  \"task_start_time\": $START_TIME," >> "$RESULT_FILE"
echo "  \"initial_file_count\": $INITIAL_COUNT," >> "$RESULT_FILE"
echo "  \"current_file_count\": $CURRENT_COUNT," >> "$RESULT_FILE"
echo "  \"new_files_count\": $NEW_FILES_COUNT," >> "$RESULT_FILE"
echo "  \"sf_files_found\": $SF_FILES_EXIST," >> "$RESULT_FILE"
echo "  \"total_data_size_bytes\": $SF_SIZE_BYTES," >> "$RESULT_FILE"
echo "  \"final_screenshot_path\": \"/sdcard/task_final.png\"" >> "$RESULT_FILE"
echo "}" >> "$RESULT_FILE"

cat "$RESULT_FILE"
echo "=== Export complete ==="