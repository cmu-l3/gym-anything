#!/bin/bash
echo "=== Exporting upload_student_photo result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Query Database for Final State
# We get the photo filename for Jason Miller
DB_RESULT=$(mysql -u $DB_USER -p"$DB_PASS" $DB_NAME -N -B -e "SELECT photo FROM students WHERE first_name='Jason' AND last_name='Miller' LIMIT 1" 2>/dev/null || echo "")

# 3. Check if file exists on disk
# OpenSIS typically stores photos in assets/student_photos/ or assets/photos/
# The DB usually stores just the filename like "123.jpg" or "photo_123.jpg"
PHOTO_ON_DISK="false"
PHOTO_PATH=""

if [ -n "$DB_RESULT" ] && [ "$DB_RESULT" != "NULL" ]; then
    # Check common locations
    POSSIBLE_PATHS=(
        "/var/www/html/opensis/assets/student_photos/$DB_RESULT"
        "/var/www/html/opensis/assets/photos/$DB_RESULT"
        "/var/www/html/opensis/assets/$DB_RESULT"
    )
    
    for path in "${POSSIBLE_PATHS[@]}"; do
        if [ -f "$path" ]; then
            PHOTO_ON_DISK="true"
            PHOTO_PATH="$path"
            break
        fi
    done
fi

# 4. Check if a new file was created in the assets directory recently
# This helps detect if the upload happened even if DB logic is complex
RECENT_UPLOAD="false"
RECENT_FILE=$(find /var/www/html/opensis/assets -type f -name "*.jpg" -newermt "@$TASK_START" 2>/dev/null | head -n 1)
if [ -n "$RECENT_FILE" ]; then
    RECENT_UPLOAD="true"
fi

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_photo_value": "$DB_RESULT",
    "photo_file_exists_on_server": $PHOTO_ON_DISK,
    "photo_path_server": "$PHOTO_PATH",
    "any_recent_upload_detected": $RECENT_UPLOAD,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="