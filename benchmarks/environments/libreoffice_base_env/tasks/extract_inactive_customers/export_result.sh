#!/bin/bash
# Export script for extract_inactive_customers
# Extracts data from the ODB file and prepares ground truth for verification

set -e
echo "=== Exporting results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Force close LibreOffice to ensure HSQLDB flushes data to the .odb file
echo "Closing LibreOffice to flush database..."
kill_libreoffice
sleep 2

# 2. Check if the ODB file was modified
ODB_PATH="/home/ga/chinook.odb"
FILE_MODIFIED="false"
if [ -f "$ODB_PATH" ]; then
    ODB_MTIME=$(stat -c %Y "$ODB_PATH" 2>/dev/null || echo "0")
    if [ "$ODB_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    ODB_SIZE=$(stat -c %s "$ODB_PATH" 2>/dev/null || echo "0")
else
    ODB_SIZE="0"
fi

# 3. Extract the HSQLDB script file to parse inserted rows
# The ODB file is a ZIP. The data is in 'database/script' (and 'database/data' for large Caching, 
# but for this size it's likely in script as INSERTs).
TEMP_EXTRACT_DIR=$(mktemp -d)
echo "Extracting ODB to $TEMP_EXTRACT_DIR..."
unzip -q -o "$ODB_PATH" -d "$TEMP_EXTRACT_DIR" || echo "Failed to unzip ODB"

SCRIPT_FILE="$TEMP_EXTRACT_DIR/database/script"
EXTRACTED_ROWS_FILE="/tmp/extracted_rows.txt"

if [ -f "$SCRIPT_FILE" ]; then
    # Grep for INSERTs into the target table (case insensitive)
    # We want lines like: INSERT INTO "InactiveCustomers" VALUES(...)
    grep -i "INSERT INTO.*InactiveCustomers" "$SCRIPT_FILE" > "$EXTRACTED_ROWS_FILE" || true
    echo "Extracted $(wc -l < "$EXTRACTED_ROWS_FILE") rows for InactiveCustomers."
else
    echo "ERROR: database/script not found in ODB"
    touch "$EXTRACTED_ROWS_FILE"
fi

# 4. Stage the original SQLite file for the verifier (Ground Truth source)
# The verifier will query this to determine what the answer *should* be.
GROUND_TRUTH_SRC="/opt/libreoffice_base_samples/Chinook_Sqlite.sqlite"
GROUND_TRUTH_DEST="/tmp/ground_truth.sqlite"
if [ -f "$GROUND_TRUTH_SRC" ]; then
    cp "$GROUND_TRUTH_SRC" "$GROUND_TRUTH_DEST"
    chmod 644 "$GROUND_TRUTH_DEST"
fi

# 5. Take final screenshot
# (Note: LO is closed now, so we can't screenshot the app, but we verify the file artifact. 
# Ideally we screenshot before closing, but we need to close to save. 
# We'll rely on trajectory screenshots for visual verification if needed.)
# We'll just take a desktop screenshot to show it closed/saved state.
take_screenshot /tmp/task_final.png

# 6. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "odb_modified": $FILE_MODIFIED,
    "odb_size_bytes": $ODB_SIZE,
    "extracted_rows_path": "$EXTRACTED_ROWS_FILE",
    "ground_truth_path": "$GROUND_TRUTH_DEST"
}
EOF

# Move result to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Cleanup extract dir
rm -rf "$TEMP_EXTRACT_DIR"

echo "Export complete. Result saved to /tmp/task_result.json"