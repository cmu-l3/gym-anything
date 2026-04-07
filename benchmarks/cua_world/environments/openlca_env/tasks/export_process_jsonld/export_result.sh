#!/bin/bash
# Post-task export for export_process_jsonld

set -e

echo "=== Exporting task results ==="

# Source utilities
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
else
    function take_screenshot() { DISPLAY=:1 scrot "$1" 2>/dev/null || true; }
    function close_openlca() { pkill -f "openLCA" 2>/dev/null || true; }
fi

# 1. Capture final state
take_screenshot /tmp/task_final.png

# 2. Gather timing and file info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_PATH="/home/ga/LCA_Results/natural_gas_electricity.zip"

# 3. Check output file
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
IS_VALID_ZIP="false"
HAS_JSON="false"
HAS_PROCESS_FOLDER="false"
KEYWORDS_FOUND="false"
FILE_SIZE_BYTES=0

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE_BYTES=$(stat -c %s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    # Check creation time
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Check zip validity
    if unzip -t "$OUTPUT_PATH" > /dev/null 2>&1; then
        IS_VALID_ZIP="true"
        
        # Inspect contents
        mkdir -p /tmp/export_check
        unzip -q "$OUTPUT_PATH" -d /tmp/export_check
        
        # Check structure
        if [ -d "/tmp/export_check/processes" ]; then
            HAS_PROCESS_FOLDER="true"
        fi
        
        if find /tmp/export_check -name "*.json" | grep -q .; then
            HAS_JSON="true"
            # Check for keywords in JSON files (case insensitive)
            if grep -riE "natural gas|electricity|power" /tmp/export_check/processes 2>/dev/null; then
                KEYWORDS_FOUND="true"
            fi
        fi
        
        rm -rf /tmp/export_check
    fi
fi

# 4. Check Database State (Did they actually import USLCI?)
DB_DIR="/home/ga/openLCA-data-1.4/databases"
CURRENT_DB_COUNT=$(ls -1d "$DB_DIR"/*/ 2>/dev/null | wc -l || echo "0")
INITIAL_DB_COUNT=$(cat /tmp/initial_db_count 2>/dev/null || echo "0")
DB_IMPORTED="false"
if [ "$CURRENT_DB_COUNT" -gt "$INITIAL_DB_COUNT" ]; then
    DB_IMPORTED="true"
fi
# Secondary check: Size of DB dir
DB_SIZE_MB=$(du -sm "$DB_DIR" 2>/dev/null | cut -f1 || echo "0")
if [ "$DB_SIZE_MB" -gt 15 ]; then
    DB_IMPORTED="true"
fi

# 5. Check if app is running
APP_RUNNING=$(pgrep -f "openLCA" > /dev/null && echo "true" || echo "false")

# 6. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE_BYTES,
    "is_valid_zip": $IS_VALID_ZIP,
    "has_json": $HAS_JSON,
    "has_process_folder": $HAS_PROCESS_FOLDER,
    "keywords_found": $KEYWORDS_FOUND,
    "db_imported": $DB_IMPORTED,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Cleanup
close_openlca

echo "Result saved to /tmp/task_result.json"