#!/bin/bash
# Export results for enable_folder_download task
set -e

echo "=== Exporting enable_folder_download results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check System Configuration (API)
# We need to verify that Folder Download is enabled and Max Size is 500
echo "Fetching system configuration..."
CONFIG_XML=$(curl -s -u admin:password "http://localhost:8082/artifactory/api/system/configuration")

# Extract values using grep/sed (simple XML parsing)
FOLDER_DOWNLOAD_ENABLED=$(echo "$CONFIG_XML" | grep -o "<folderDownloadEnabled>.*</folderDownloadEnabled>" | sed 's/<[^>]*>//g')
MAX_DOWNLOAD_SIZE=$(echo "$CONFIG_XML" | grep -o "<maxFolderDownloadSizeMbytes>.*</maxFolderDownloadSizeMbytes>" | sed 's/<[^>]*>//g')

echo "Config state: Enabled=$FOLDER_DOWNLOAD_ENABLED, MaxSize=$MAX_DOWNLOAD_SIZE"

# 4. Check Output ZIP File
ZIP_PATH="/home/ga/Desktop/commons-io-package.zip"
ZIP_EXISTS="false"
ZIP_SIZE="0"
ZIP_VALID="false"
HAS_JAR="false"
FILE_TIME="0"

if [ -f "$ZIP_PATH" ]; then
    ZIP_EXISTS="true"
    ZIP_SIZE=$(stat -c %s "$ZIP_PATH")
    FILE_TIME=$(stat -c %Y "$ZIP_PATH")
    
    # Verify validity and content
    if unzip -t "$ZIP_PATH" >/dev/null 2>&1; then
        ZIP_VALID="true"
        # Check for the JAR file inside
        if unzip -l "$ZIP_PATH" | grep -q "commons-io-2.15.1.jar"; then
            HAS_JAR="true"
        fi
    fi
fi

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config_folder_download_enabled": "$FOLDER_DOWNLOAD_ENABLED",
    "config_max_size": "$MAX_DOWNLOAD_SIZE",
    "zip_exists": $ZIP_EXISTS,
    "zip_size_bytes": $ZIP_SIZE,
    "zip_valid": $ZIP_VALID,
    "zip_contains_jar": $HAS_JAR,
    "zip_mtime": $FILE_TIME,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="