#!/bin/bash
echo "=== Exporting add_facility_logo_badge result ==="

source /workspace/scripts/task_utils.sh

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# ============================================================
# 1. Check for File Modifications (Programmatic Signal 1)
# ============================================================
echo "Checking for modified badge templates..."
MODIFIED_FILES_COUNT=0
MODIFIED_FILES_LIST=""

BADGE_DIRS=(
    "/home/ga/.wine/drive_c/Program Files/Jolly Technologies/Lobby Track"
    "/home/ga/.wine/drive_c/ProgramData/Jolly Technologies/Lobby Track"
    "/home/ga/LobbyTrack"
    "/home/ga/.wine/drive_c/users/ga/Application Data/Jolly Technologies"
)

# Create a temp file to store findings
TEMP_FINDINGS=$(mktemp)

for dir in "${BADGE_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        # Find files modified AFTER task start
        # Look for badge templates (.badge, .btp), XML configs, or database updates (.mdb)
        find "$dir" -type f \( -iname "*.badge" -o -iname "*.btp" -o -iname "*.xml" -o -iname "*.mdb" -o -iname "*.db" \) -newermt "@$TASK_START" 2>/dev/null >> "$TEMP_FINDINGS" || true
    fi
done

MODIFIED_FILES_COUNT=$(wc -l < "$TEMP_FINDINGS")
if [ "$MODIFIED_FILES_COUNT" -gt 0 ]; then
    MODIFIED_FILES_LIST=$(cat "$TEMP_FINDINGS" | tr '\n' ', ')
fi
rm -f "$TEMP_FINDINGS"

echo "Found $MODIFIED_FILES_COUNT modified files: $MODIFIED_FILES_LIST"

# ============================================================
# 2. Check for Logo Reference/Import (Programmatic Signal 2)
# ============================================================
echo "Checking for logo file usage..."
LOGO_IMPORTED="false"

# Check if the logo was copied to any app directory (common behavior for import)
IMPORTED_LOGOS=$(find /home/ga/.wine/drive_c -name "company_logo*" -not -path "*/Desktop/*" -newermt "@$TASK_START" 2>/dev/null | wc -l)

# Check if any config file contains reference to the logo path/name
LOGO_REF_FOUND="false"
if grep -r "company_logo" "${BADGE_DIRS[@]}" 2>/dev/null | grep -q "company_logo"; then
    LOGO_REF_FOUND="true"
fi

if [ "$IMPORTED_LOGOS" -gt 0 ] || [ "$LOGO_REF_FOUND" = "true" ]; then
    LOGO_IMPORTED="true"
fi

echo "Logo imported signal: $LOGO_IMPORTED (Copies: $IMPORTED_LOGOS, Refs: $LOGO_REF_FOUND)"

# ============================================================
# 3. Create Result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "modified_files_count": $MODIFIED_FILES_COUNT,
    "modified_files_list": "$MODIFIED_FILES_LIST",
    "logo_imported_programmatic": $LOGO_IMPORTED,
    "logo_ref_found": $LOGO_REF_FOUND,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="