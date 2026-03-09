#!/bin/bash
echo "=== Exporting task results: install_custom_csl ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final_state.png

# 2. Context Variables
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
DB_PATH=$(get_jurism_db)
STYLE_ID="http://www.zotero.org/styles/firm-standard-2025"
STYLE_FILENAME="firm-standard-2025.csl"
DOCS_PATH="/home/ga/Documents/$STYLE_FILENAME"

# 3. Check Database
STYLE_IN_DB="false"
if [ -n "$DB_PATH" ]; then
    DB_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM styles WHERE styleID='$STYLE_ID';" 2>/dev/null || echo "0")
    if [ "$DB_COUNT" -ge 1 ]; then
        STYLE_IN_DB="true"
    fi
fi

# 4. Check File System (Profile Directory)
STYLE_FILE_INSTALLED="false"
INSTALLED_FILE_TIMESTAMP="0"
PROFILE_DIR=$(dirname "$DB_PATH")
STYLES_DIR="$PROFILE_DIR/styles"
INSTALLED_PATH="$STYLES_DIR/$STYLE_FILENAME"
ACTUAL_INSTALLED_PATH=""

# Check exact filename match
if [ -f "$INSTALLED_PATH" ]; then
    STYLE_FILE_INSTALLED="true"
    ACTUAL_INSTALLED_PATH="$INSTALLED_PATH"
else
    # Fallback: Check for any file containing the ID (Zotero sometimes renames to lowercase or ID-based name)
    FOUND_FILE=$(grep -l "$STYLE_ID" "$STYLES_DIR"/*.csl 2>/dev/null | head -n 1)
    if [ -n "$FOUND_FILE" ]; then
        STYLE_FILE_INSTALLED="true"
        ACTUAL_INSTALLED_PATH="$FOUND_FILE"
    fi
fi

# Get timestamp if file found
if [ -n "$ACTUAL_INSTALLED_PATH" ]; then
    INSTALLED_FILE_TIMESTAMP=$(stat -c %Y "$ACTUAL_INSTALLED_PATH" 2>/dev/null || echo "0")
fi

# 5. Create JSON Result
# Use temp file to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "style_in_db": $STYLE_IN_DB,
    "style_file_installed": $STYLE_FILE_INSTALLED,
    "installed_file_path": "$ACTUAL_INSTALLED_PATH",
    "installed_file_timestamp": $INSTALLED_FILE_TIMESTAMP,
    "screenshot_path": "/tmp/task_final_state.png"
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