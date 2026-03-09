#!/bin/bash
set -e
echo "=== Exporting define_relationships result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot before closing app
take_screenshot /tmp/task_final.png

# 1. Gracefully close LibreOffice to ensure data is saved to disk
# (ODB files are often only updated on save or exit)
echo "Closing LibreOffice to flush changes..."
pkill -f "soffice" || true
sleep 3
pkill -9 -f "soffice" || true
sleep 1

# 2. Check if ODB file was modified
ODB_PATH="/home/ga/chinook.odb"
INITIAL_HASH=$(cat /tmp/initial_odb_hash.txt 2>/dev/null || echo "0")
CURRENT_HASH=$(md5sum "$ODB_PATH" 2>/dev/null | awk '{print $1}' || echo "1")

FILE_MODIFIED="false"
if [ "$INITIAL_HASH" != "$CURRENT_HASH" ]; then
    FILE_MODIFIED="true"
    echo "ODB file modification detected."
else
    echo "WARNING: ODB file hash unchanged."
fi

# 3. Extract the HSQLDB script from the ODB file
# ODB is a ZIP file; the schema is in 'database/script'
SCRIPT_EXTRACT_PATH="/tmp/extracted_script"
rm -f "$SCRIPT_EXTRACT_PATH"

if command -v unzip >/dev/null; then
    echo "Extracting database script from ODB..."
    unzip -p "$ODB_PATH" "database/script" > "$SCRIPT_EXTRACT_PATH" 2>/dev/null || echo "Extraction failed"
else
    echo "ERROR: unzip not found"
fi

SCRIPT_EXISTS="false"
SCRIPT_SIZE=0
if [ -f "$SCRIPT_EXTRACT_PATH" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_SIZE=$(stat -c%s "$SCRIPT_EXTRACT_PATH")
    echo "Extracted script size: $SCRIPT_SIZE bytes"
fi

# 4. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_modified": $FILE_MODIFIED,
    "initial_hash": "$INITIAL_HASH",
    "final_hash": "$CURRENT_HASH",
    "script_extracted": $SCRIPT_EXISTS,
    "script_size": $SCRIPT_SIZE,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move files to standard locations for verifier
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

if [ "$SCRIPT_EXISTS" = "true" ]; then
    cp "$SCRIPT_EXTRACT_PATH" /tmp/database_script.sql
    chmod 644 /tmp/database_script.sql
fi

echo "Result exported to /tmp/task_result.json"
echo "Database script exported to /tmp/database_script.sql"
echo "=== Export complete ==="