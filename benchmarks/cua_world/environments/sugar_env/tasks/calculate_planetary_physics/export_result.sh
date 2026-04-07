#!/bin/bash
# Do NOT use set -e
echo "=== Exporting calculate_planetary_physics task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot for VLM verification
su - ga -c "$SUGAR_ENV scrot /tmp/calculate_task_end.png" 2>/dev/null || true

RESULTS_FILE="/home/ga/Documents/orbital_results.txt"
TASK_START=$(cat /tmp/calculate_planetary_physics_start_ts 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_SIZE=0
FILE_MODIFIED="false"

if [ -f "$RESULTS_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$RESULTS_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$RESULTS_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    echo "Found: $RESULTS_FILE ($FILE_SIZE bytes, mtime=$FILE_MTIME, task_start=$TASK_START)"
fi

# Extract text content safely via python to preserve JSON integrity
python3 << 'PYEOF' > /tmp/calculate_analysis.json 2>/dev/null || echo '{"error":"parse_failed"}' > /tmp/calculate_analysis.json
import json
import os

result = {"text_content": ""}
try:
    if os.path.exists("/home/ga/Documents/orbital_results.txt"):
        with open("/home/ga/Documents/orbital_results.txt", "r", encoding="utf-8", errors="replace") as f:
            result["text_content"] = f.read()[:5000]  # Cap at 5KB to prevent bloat
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

TEXT_CONTENT=$(python3 -c "import json, sys; d=json.load(sys.stdin); print(json.dumps(d.get('text_content','')))" < /tmp/calculate_analysis.json)

# Check Sugar Journal for the calculation session
JOURNAL_DIR="/home/ga/.sugar/default/datastore"
JOURNAL_FOUND="false"
JOURNAL_ACTIVITY=""
JOURNAL_CREATED_AFTER_START="false"

if [ -d "$JOURNAL_DIR" ]; then
    # Look for the required title in the metadata files
    MATCH=$(find "$JOURNAL_DIR" -name "title" -exec grep -l "Orbital Mechanics Problem Set" {} \; 2>/dev/null | head -1)
    
    if [ -n "$MATCH" ]; then
        JOURNAL_FOUND="true"
        ENTRY_DIR=$(dirname "$(dirname "$MATCH")")
        
        # Identify the activity that created this entry
        if [ -f "$ENTRY_DIR/metadata/activity" ]; then
            JOURNAL_ACTIVITY=$(cat "$ENTRY_DIR/metadata/activity" 2>/dev/null || echo "")
        fi
        
        # Check if the entry was created/modified during the task
        ENTRY_MTIME=$(stat --format=%Y "$MATCH" 2>/dev/null || echo "0")
        if [ "$ENTRY_MTIME" -gt "$TASK_START" ]; then
            JOURNAL_CREATED_AFTER_START="true"
        fi
        
        echo "Found Journal entry at $ENTRY_DIR (Activity: $JOURNAL_ACTIVITY)"
    else
        echo "No journal entry matching 'Orbital Mechanics Problem Set' was found."
    fi
fi

# Assemble export JSON
cat > /tmp/calculate_planetary_physics_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_modified": $FILE_MODIFIED,
    "text_content": $TEXT_CONTENT,
    "journal_found": $JOURNAL_FOUND,
    "journal_activity": "$JOURNAL_ACTIVITY",
    "journal_created_after_start": $JOURNAL_CREATED_AFTER_START
}
EOF

chmod 666 /tmp/calculate_planetary_physics_result.json
echo "Result saved to /tmp/calculate_planetary_physics_result.json"
echo "=== Export complete ==="