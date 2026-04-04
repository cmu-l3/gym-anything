#!/bin/bash
set -e
echo "=== Exporting configure_agent_soundboard results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# --- DATA GATHERING ---

# Helper function to run SQL in container
run_sql() {
    docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "$1" 2>/dev/null
}

# 1. Check System Settings
echo "Checking system settings..."
SETTINGS_ROW=$(run_sql "SELECT agent_soundboards, central_sound_control_active FROM system_settings LIMIT 1")
AGENT_SB_SETTING=$(echo "$SETTINGS_ROW" | awk '{print $1}')
CENTRAL_SOUND_SETTING=$(echo "$SETTINGS_ROW" | awk '{print $2}')

# 2. Check Soundboard Existence
echo "Checking soundboard..."
SB_EXISTS=$(run_sql "SELECT COUNT(*) FROM vicidial_soundboards WHERE soundboard_id='LEGAL_SB'")

# 3. Check Audio File Upload (Database Record)
echo "Checking audio store..."
AUDIO_RECORD_EXISTS=$(run_sql "SELECT COUNT(*) FROM vicidial_audio_store WHERE audio_filename='legal_disclosure'")

# 4. Check Audio File on Disk (Container)
echo "Checking audio file on disk..."
if docker exec vicidial test -f /var/lib/asterisk/sounds/legal_disclosure.wav; then
    AUDIO_FILE_ON_DISK="1"
else
    AUDIO_FILE_ON_DISK="0"
fi

# 5. Check Linkage (Soundboard <-> Audio)
echo "Checking soundboard audio link..."
LINKAGE_COUNT=$(run_sql "SELECT COUNT(*) FROM vicidial_soundboard_audio WHERE soundboard_id='LEGAL_SB' AND audio_file='legal_disclosure'")

# --- EXPORT JSON ---

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "settings": {
        "agent_soundboards": "${AGENT_SB_SETTING:-0}",
        "central_sound_control": "${CENTRAL_SOUND_SETTING:-0}"
    },
    "soundboard": {
        "exists_count": ${SB_EXISTS:-0},
        "id": "LEGAL_SB"
    },
    "audio": {
        "db_record_exists": ${AUDIO_RECORD_EXISTS:-0},
        "file_on_disk": ${AUDIO_FILE_ON_DISK:-0},
        "filename": "legal_disclosure.wav"
    },
    "linkage": {
        "count": ${LINKAGE_COUNT:-0}
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location with read permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result JSON content:"
cat /tmp/task_result.json

echo "=== Export complete ==="