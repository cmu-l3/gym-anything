#!/bin/bash
echo "=== Exporting backup_visitor_database results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Capture final state screenshot
take_screenshot /tmp/task_final.png

# Paths
BACKUP_DIR="/home/ga/Documents/LobbyTrackBackup"
MANIFEST_FILE="$BACKUP_DIR/backup_manifest.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
GROUND_TRUTH_SIZE=$(cat /tmp/ground_truth_db_size.txt 2>/dev/null || echo "0")

# Initialize result variables
BACKUP_DIR_EXISTS="false"
BACKUP_FILE_FOUND="false"
BACKUP_FILENAME=""
BACKUP_SIZE="0"
BACKUP_MTIME="0"
BACKUP_CREATED_DURING_TASK="false"
VALID_EXTENSION="false"
IS_BINARY="false"
MANIFEST_EXISTS="false"
MANIFEST_CONTENT=""

# Check Directory
if [ -d "$BACKUP_DIR" ]; then
    BACKUP_DIR_EXISTS="true"
    
    # Check for backup file (lobby_track_backup.*)
    # Find file matching pattern, ignoring case, excluding the manifest
    FOUND_FILE=$(find "$BACKUP_DIR" -maxdepth 1 -type f -iname "lobby_track_backup.*" -not -name "backup_manifest.txt" | head -n 1)
    
    if [ -n "$FOUND_FILE" ]; then
        BACKUP_FILE_FOUND="true"
        BACKUP_FILENAME=$(basename "$FOUND_FILE")
        BACKUP_SIZE=$(stat -c%s "$FOUND_FILE" 2>/dev/null || echo "0")
        BACKUP_MTIME=$(stat -c%Y "$FOUND_FILE" 2>/dev/null || echo "0")
        
        # Check timestamp
        if [ "$BACKUP_MTIME" -gt "$TASK_START" ]; then
            BACKUP_CREATED_DURING_TASK="true"
        fi
        
        # Check extension
        if echo "$BACKUP_FILENAME" | grep -qiE "\.(sdf|mdb|accdb|db|sqlite|sqlite3|xml|bak)$"; then
            VALID_EXTENSION="true"
        fi
        
        # Check if binary (simple heuristic)
        if file "$FOUND_FILE" | grep -qiE "data|database|SQLite|Microsoft|Composite Doc"; then
            IS_BINARY="true"
        fi
    fi
    
    # Check Manifest
    if [ -f "$MANIFEST_FILE" ]; then
        MANIFEST_EXISTS="true"
        # Read content (safely, first 1KB)
        MANIFEST_CONTENT=$(head -c 1024 "$MANIFEST_FILE" | sed 's/"/\\"/g' | tr '\n' ' ')
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "backup_dir_exists": $BACKUP_DIR_EXISTS,
    "backup_file_found": $BACKUP_FILE_FOUND,
    "backup_filename": "$BACKUP_FILENAME",
    "backup_size_bytes": $BACKUP_SIZE,
    "ground_truth_size_bytes": $GROUND_TRUTH_SIZE,
    "backup_created_during_task": $BACKUP_CREATED_DURING_TASK,
    "valid_extension": $VALID_EXTENSION,
    "is_binary_format": $IS_BINARY,
    "manifest_exists": $MANIFEST_EXISTS,
    "manifest_content_preview": "$MANIFEST_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="