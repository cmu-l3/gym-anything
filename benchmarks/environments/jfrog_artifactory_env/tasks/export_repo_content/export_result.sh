#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

EXPORT_DIR="/home/ga/repo_export"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize result variables
DIR_EXISTS="false"
DIR_CREATED_DURING_TASK="false"
ARTIFACT_FOUND="false"
METADATA_FOUND="false"
TOTAL_SIZE="0"
ARTIFACT_COUNT="0"

# Check export directory
if [ -d "$EXPORT_DIR" ]; then
    DIR_EXISTS="true"
    
    # Check timestamp (modification time of the directory should be >= task start)
    DIR_MTIME=$(stat -c %Y "$EXPORT_DIR" 2>/dev/null || echo "0")
    if [ "$DIR_MTIME" -ge "$TASK_START" ]; then
        DIR_CREATED_DURING_TASK="true"
    fi
    
    # Find the specific artifact we expect
    if find "$EXPORT_DIR" -name "commons-lang3-3.14.0.jar" 2>/dev/null | grep -q .; then
        ARTIFACT_FOUND="true"
    fi
    
    # Check for metadata
    # When "Include Metadata" is checked, Artifactory exports folder metadata.
    # We look for xml files or hidden folder metadata files.
    if find "$EXPORT_DIR" -name "*.xml" -o -name ".jfrog" 2>/dev/null | grep -q .; then
        METADATA_FOUND="true"
    fi
    
    # Calculate total size of the export
    TOTAL_SIZE=$(du -sb "$EXPORT_DIR" 2>/dev/null | cut -f1 || echo "0")
    
    # Count files
    ARTIFACT_COUNT=$(find "$EXPORT_DIR" -type f | wc -l)
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "export_dir_exists": $DIR_EXISTS,
    "dir_created_during_task": $DIR_CREATED_DURING_TASK,
    "artifact_found": $ARTIFACT_FOUND,
    "metadata_found": $METADATA_FOUND,
    "total_size_bytes": $TOTAL_SIZE,
    "file_count": $ARTIFACT_COUNT,
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="