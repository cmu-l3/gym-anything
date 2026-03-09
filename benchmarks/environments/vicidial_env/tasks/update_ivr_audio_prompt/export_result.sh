#!/bin/bash
echo "=== Exporting Update IVR Audio Prompt Result ==="

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if Audio File Exists in Container
# Vicidial places uploaded audio in /var/lib/asterisk/sounds/ (usually)
# We verify if the file exists inside the docker container
AUDIO_FILE_EXISTS="false"
AUDIO_FILE_SIZE="0"
AUDIO_FILE_MTIME="0"

# Check for wav, gsm, or sln (Vicidial might convert it)
if docker exec vicidial ls /var/lib/asterisk/sounds/holiday_greeting_2026.wav >/dev/null 2>&1; then
    AUDIO_FILE_EXISTS="true"
    # Get size and mtime from inside container
    AUDIO_FILE_SIZE=$(docker exec vicidial stat -c %s /var/lib/asterisk/sounds/holiday_greeting_2026.wav)
    # Get mtime (epoch)
    AUDIO_FILE_MTIME=$(docker exec vicidial stat -c %Y /var/lib/asterisk/sounds/holiday_greeting_2026.wav)
fi

# 2. Check Database for Call Menu Configuration
# Query the prompt setting for MAIN_IVR
MENU_PROMPT_VALUE=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT menu_prompt FROM vicidial_call_menu WHERE menu_id='MAIN_IVR'" 2>/dev/null || echo "")

# 3. Check if file was uploaded DURING the task
FILE_UPLOADED_DURING_TASK="false"
if [ "$AUDIO_FILE_EXISTS" = "true" ]; then
    if [ "$AUDIO_FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_UPLOADED_DURING_TASK="true"
    fi
fi

# 4. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "audio_file_exists": $AUDIO_FILE_EXISTS,
    "audio_file_size": $AUDIO_FILE_SIZE,
    "audio_file_mtime": $AUDIO_FILE_MTIME,
    "file_uploaded_during_task": $FILE_UPLOADED_DURING_TASK,
    "menu_prompt_value": "$MENU_PROMPT_VALUE",
    "initial_prompt_value": "$(cat /tmp/initial_prompt.txt 2>/dev/null)",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="