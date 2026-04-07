#!/system/bin/sh
echo "=== Exporting perform_data_backup results ==="

# 1. Capture final screenshot
screencap -p /sdcard/task_final.png

# 2. Get timing info
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# 3. Search for backup files created AFTER task start
# Android shell 'find' is limited, so we iterate common paths
BACKUP_FOUND="false"
BACKUP_FILE=""
BACKUP_SIZE="0"
BACKUP_TIME="0"

# Define paths to search
SEARCH_DIRS="/sdcard/com.ds.avare /sdcard/Android/data/com.ds.avare/files /sdcard/Download"

echo "Searching for new backup files..."
for DIR in $SEARCH_DIRS; do
    if [ -d "$DIR" ]; then
        # List files, check timestamps
        # Note: Android ls -l usually gives date, not epoch. stat is better if available.
        # We'll rely on the fact that we cleaned files in setup, so ANY file here matching pattern is likely the one.
        # However, specifically checking modification time is safer.
        
        for FILE in "$DIR"/*; do
            if [ -f "$FILE" ]; then
                # Check for backup-like names (json, zip, user)
                case "$FILE" in 
                    *backup*|*.json|*user*)
                        # Get modification time (epoch)
                        MTIME=$(stat -c %Y "$FILE" 2>/dev/null)
                        
                        if [ "$MTIME" -gt "$TASK_START" ]; then
                            BACKUP_FOUND="true"
                            BACKUP_FILE="$FILE"
                            BACKUP_SIZE=$(stat -c %s "$FILE" 2>/dev/null)
                            BACKUP_TIME="$MTIME"
                            echo "Found valid backup: $FILE (Time: $MTIME, Size: $BACKUP_SIZE)"
                            break 2 
                        fi
                        ;;
                esac
            fi
        done
    fi
done

# 4. Check if app is in foreground (simple check)
APP_FOCUSED="false"
if dumpsys window | grep mCurrentFocus | grep -q "com.ds.avare"; then
    APP_FOCUSED="true"
fi

# 5. Create JSON result
# Note: Using a temp file on sdcard to ensure write permissions
JSON_PATH="/sdcard/task_result.json"
echo "{" > $JSON_PATH
echo "  \"task_start\": $TASK_START," >> $JSON_PATH
echo "  \"task_end\": $TASK_END," >> $JSON_PATH
echo "  \"backup_found\": $BACKUP_FOUND," >> $JSON_PATH
echo "  \"backup_file_path\": \"$BACKUP_FILE\"," >> $JSON_PATH
echo "  \"backup_file_size\": $BACKUP_SIZE," >> $JSON_PATH
echo "  \"backup_timestamp\": $BACKUP_TIME," >> $JSON_PATH
echo "  \"app_focused\": $APP_FOCUSED," >> $JSON_PATH
echo "  \"screenshot_path\": \"/sdcard/task_final.png\"" >> $JSON_PATH
echo "}" >> $JSON_PATH

echo "Result exported to $JSON_PATH"
cat $JSON_PATH
echo "=== Export complete ==="