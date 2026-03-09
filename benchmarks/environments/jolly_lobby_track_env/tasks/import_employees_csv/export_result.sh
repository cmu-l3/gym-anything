#!/bin/bash
echo "=== Exporting import_employees_csv result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Locate the Database File
DB_FILE=$(find /home/ga/.wine/drive_c -name "LobbyTrack*.mdb" -o -name "LobbyTrack*.sdf" 2>/dev/null | head -1)
DB_EXISTS="false"
DB_MODIFIED="false"
DB_PATH=""
NAMES_FOUND_COUNT=0
EMAILS_FOUND_COUNT=0

if [ -n "$DB_FILE" ] && [ -f "$DB_FILE" ]; then
    DB_EXISTS="true"
    DB_PATH="$DB_FILE"
    
    # Check modification time
    CURRENT_MTIME=$(stat -c %Y "$DB_FILE")
    INITIAL_MTIME=$(cat /tmp/initial_db_mtime.txt 2>/dev/null || echo "0")
    TASK_START=$(cat /tmp/import_employees_csv_start_time 2>/dev/null || echo "0")
    
    # If MTIME > INITIAL_MTIME and MTIME > TASK_START
    if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ] && [ "$CURRENT_MTIME" -gt "$TASK_START" ]; then
        DB_MODIFIED="true"
    fi

    # Check for presence of names and emails using strings/grep
    # MDB files are binary but often store strings in ANSI or UTF-16
    # We use 'strings' to extract printable chars and grep from there
    
    DB_STRINGS=$(strings -e l "$DB_FILE" 2>/dev/null) # Try UTF-16 LE
    DB_STRINGS_A=$(strings "$DB_FILE" 2>/dev/null)    # Try ANSI
    ALL_STRINGS="${DB_STRINGS}\n${DB_STRINGS_A}"
    
    # List of expected names
    EXPECTED_NAMES=("Alice Intern" "Bob Intern" "Charlie Intern" "Dana Intern" "Evan Intern")
    for name in "${EXPECTED_NAMES[@]}"; do
        if echo -e "$ALL_STRINGS" | grep -qi "$name"; then
            NAMES_FOUND_COUNT=$((NAMES_FOUND_COUNT + 1))
        fi
    done
    
    # List of expected emails (to verify mapping)
    EXPECTED_EMAILS=("alice.intern@example.com" "bob.intern@example.com" "charlie.intern@example.com" "dana.intern@example.com" "evan.intern@example.com")
    for email in "${EXPECTED_EMAILS[@]}"; do
        if echo -e "$ALL_STRINGS" | grep -qi "$email"; then
            EMAILS_FOUND_COUNT=$((EMAILS_FOUND_COUNT + 1))
        fi
    done
else
    echo "Database file not found for verification."
fi

# 2. Check if Lobby Track is still running
APP_RUNNING="false"
if pgrep -f "LobbyTrack" > /dev/null; then
    APP_RUNNING="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "db_exists": $DB_EXISTS,
    "db_modified": $DB_MODIFIED,
    "names_found_count": $NAMES_FOUND_COUNT,
    "emails_found_count": $EMAILS_FOUND_COUNT,
    "total_expected": 5,
    "app_running": $APP_RUNNING,
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
echo "=== Export complete ==="