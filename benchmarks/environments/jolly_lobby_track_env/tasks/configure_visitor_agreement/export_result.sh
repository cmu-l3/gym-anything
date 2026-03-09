#!/bin/bash
set -e
echo "=== Exporting visitor agreement configuration results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPECTED_SCREENSHOT="/home/ga/visitor_agreement_configured.png"

# 1. Check Screenshot Evidence
SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE="0"
SCREENSHOT_CREATED_DURING_TASK="false"

if [ -f "$EXPECTED_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c%s "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    FCREATED=$(stat -c%Y "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    
    if [ "$FCREATED" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check for Configuration Persistence (Text Search)
# Search for the agreement text in potential config files modified during the task
echo "Searching for agreement text in modified files..."
AGREEMENT_FOUND_IN_CONFIG="false"
MATCHED_PHRASES=""

# Find files modified after task start
MODIFIED_FILES=$(find /home/ga/.wine/drive_c -type f -newer /tmp/task_start_time.txt \
    \( -iname "*.sdf" -o -iname "*.config" -o -iname "*.xml" -o -iname "*.ini" \
    -o -iname "*.json" -o -iname "*.dat" -o -iname "*.db" -o -iname "*.mdb" -o -iname "*.txt" \) \
    2>/dev/null || true)

# Also dump registry to a text file to check if settings are stored there
regedit /E /tmp/registry_dump.reg "HKEY_CURRENT_USER" 2>/dev/null || true
if [ -f /tmp/registry_dump.reg ]; then
    MODIFIED_FILES="$MODIFIED_FILES /tmp/registry_dump.reg"
fi

# Phrases to search for
PHRASES=("confidential information" "Morrison & Associates" "security screening")

for phrase in "${PHRASES[@]}"; do
    # Use strings to handle binary files (like .sdf or .db)
    if echo "$MODIFIED_FILES" | xargs strings 2>/dev/null | grep -qi "$phrase"; then
        AGREEMENT_FOUND_IN_CONFIG="true"
        MATCHED_PHRASES="${MATCHED_PHRASES}|${phrase}"
    fi
done

# 3. Check for File Modification Activity
CONFIG_MODIFIED="false"
# Compare current state with initial state (excluding the reg dump we just made)
CURRENT_STATE=$(find /home/ga/.wine/drive_c -iname "*.sdf" -o -iname "*.config" -o -iname "*.xml" -o -iname "*.ini" 2>/dev/null | while read f; do
    stat -c '%Y %n' "$f" 2>/dev/null
done || true)

# Simple diff check
if [ "$CURRENT_STATE" != "$(cat /tmp/initial_config_state.txt 2>/dev/null || echo "")" ]; then
    CONFIG_MODIFIED="true"
fi

# 4. Final System State Screenshot (backup evidence)
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size": $SCREENSHOT_SIZE,
    "screenshot_created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
    "screenshot_path": "$EXPECTED_SCREENSHOT",
    "agreement_text_found_in_config": $AGREEMENT_FOUND_IN_CONFIG,
    "matched_phrases": "$MATCHED_PHRASES",
    "config_files_modified": $CONFIG_MODIFIED,
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="