#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

# Load task config
if [ ! -f /tmp/task_config.json ]; then
    echo "ERROR: Task config not found!"
    exit 1
fi

SOURCE_ID=$(jq -r '.source_case_id' /tmp/task_config.json)
TARGET_ID=$(jq -r '.target_case_id' /tmp/task_config.json)
ORIG_HASH=$(jq -r '.original_hash' /tmp/task_config.json)
FILENAME=$(jq -r '.filename' /tmp/task_config.json)

echo "Checking Source Case: $SOURCE_ID"
echo "Checking Target Case: $TARGET_ID"

# 1. Check Source Case (Should be empty of the specific file)
SOURCE_DOCS=$(arkcase_api GET "plugin/complaint/${SOURCE_ID}/documents")
# Check if our filename exists in the list
SOURCE_HAS_FILE=$(echo "$SOURCE_DOCS" | jq -r --arg fn "$FILENAME" '.[] | select(.title == $fn or .name == $fn) | .id')

if [ -z "$SOURCE_HAS_FILE" ]; then
    SOURCE_CLEARED="true"
    echo "Source case is clear."
else
    SOURCE_CLEARED="false"
    echo "Source case still contains document ID: $SOURCE_HAS_FILE"
fi

# 2. Check Target Case (Should have the file)
TARGET_DOCS=$(arkcase_api GET "plugin/complaint/${TARGET_ID}/documents")
TARGET_DOC_ID=$(echo "$TARGET_DOCS" | jq -r --arg fn "$FILENAME" '.[] | select(.title == $fn or .name == $fn) | .id')

TARGET_HAS_FILE="false"
HASH_MATCH="false"
TARGET_DOC_NAME=""

if [ -n "$TARGET_DOC_ID" ] && [ "$TARGET_DOC_ID" != "null" ]; then
    TARGET_HAS_FILE="true"
    echo "Target case has document ID: $TARGET_DOC_ID"
    
    # Get the actual filename from the record to verify name accuracy
    TARGET_DOC_NAME=$(echo "$TARGET_DOCS" | jq -r --arg id "$TARGET_DOC_ID" '.[] | select(.id == $id) | .name // .title')

    # 3. Verify Content Integrity (Download and Hash)
    # We need to download the file. 
    # ArkCase API for download usually involves getting a download URL or direct stream
    # Try generic download endpoint: api/v1/documents/{id}/download or similar.
    # Based on general ArkCase/Alfresco patterns, we might need to search for the download link in the doc object
    # Or try constructing it.
    
    echo "Downloading for verification..."
    DOWNLOAD_PATH="/tmp/verified_doc.pdf"
    
    # Attempt download
    curl -sk -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
        -o "$DOWNLOAD_PATH" \
        "${ARKCASE_URL}/api/v1/document/${TARGET_DOC_ID}/download"
        
    if [ -f "$DOWNLOAD_PATH" ]; then
        DOWNLOADED_HASH=$(md5sum "$DOWNLOAD_PATH" | awk '{print $1}')
        echo "Downloaded Hash: $DOWNLOADED_HASH"
        echo "Original Hash:   $ORIG_HASH"
        
        if [ "$DOWNLOADED_HASH" == "$ORIG_HASH" ]; then
            HASH_MATCH="true"
        fi
    fi
else
    echo "Target case does not contain the document."
fi

# 4. Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 5. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 6. Generate Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" <<EOF
{
    "source_cleared": $SOURCE_CLEARED,
    "target_has_file": $TARGET_HAS_FILE,
    "target_filename": "$TARGET_DOC_NAME",
    "expected_filename": "$FILENAME",
    "hash_match": $HASH_MATCH,
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="