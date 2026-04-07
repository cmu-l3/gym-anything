#!/system/bin/sh
# Post-task hook: Export farmOS state for spray_day_audit_reconciliation verification.
# Collects: UI hierarchy, app data dump, screenshot, and structured result JSON.

echo "=== Exporting spray_day_audit_reconciliation state ==="

PACKAGE="org.farmos.app"
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# ---------------------------------------------------------------------------
# 1. Navigate back to Tasks list (exit any open form / drawer)
# ---------------------------------------------------------------------------
input keyevent KEYCODE_BACK
sleep 1
input keyevent KEYCODE_BACK
sleep 1
input keyevent KEYCODE_BACK
sleep 2

# ---------------------------------------------------------------------------
# 2. Capture final screenshot
# ---------------------------------------------------------------------------
screencap -p /sdcard/final_screenshot_spray_audit.png 2>/dev/null

# ---------------------------------------------------------------------------
# 3. Dump UI hierarchy (Tasks list should be visible)
# ---------------------------------------------------------------------------
rm -f /sdcard/ui_dump_spray_audit.xml 2>/dev/null
uiautomator dump /sdcard/ui_dump_spray_audit.xml > /dev/null 2>&1

UI_DUMP_EXISTS="false"
UI_DUMP_SIZE=0
if [ -f /sdcard/ui_dump_spray_audit.xml ]; then
    UI_DUMP_EXISTS="true"
    UI_DUMP_SIZE=$(stat -c %s /sdcard/ui_dump_spray_audit.xml 2>/dev/null || echo "0")
fi

# ---------------------------------------------------------------------------
# 4. Dump app internal data (IndexedDB/LevelDB/SQLite strings)
# ---------------------------------------------------------------------------
DATA_DUMP="/data/local/tmp/app_data_dump_spray_audit.txt"
> "$DATA_DUMP"

echo "Dumping app data strings..."
find /data/data/$PACKAGE/ -type f \( -name "*.ldb" -o -name "*.log" -o -name "*.db" -o -name "*.sqlite" -o -name "00000*" \) 2>/dev/null | while read f; do
    strings "$f" 2>/dev/null >> "$DATA_DUMP"
done

find /data/data/$PACKAGE/shared_prefs/ -name "*.xml" 2>/dev/null | while read f; do
    cat "$f" 2>/dev/null >> "$DATA_DUMP"
done

DUMP_SIZE=$(stat -c %s "$DATA_DUMP" 2>/dev/null || echo "0")

# Create lowercase copy for case-insensitive searches
DUMP_LOWER="/data/local/tmp/app_data_dump_spray_audit_lower.txt"
if [ -s "$DATA_DUMP" ]; then
    cat "$DATA_DUMP" | tr 'A-Z' 'a-z' > "$DUMP_LOWER" 2>/dev/null || true
else
    > "$DUMP_LOWER"
fi

# ---------------------------------------------------------------------------
# 5. Check for specific content in dumped data
# ---------------------------------------------------------------------------

# --- Log names ---
HAS_LOG_ROOTWORM="false"
if grep -q "rootworm damage assessment" "$DUMP_LOWER" 2>/dev/null; then
    HAS_LOG_ROOTWORM="true"
fi

HAS_LOG_BIFENTHRIN="false"
if grep -q "bifenthrin 2ec application" "$DUMP_LOWER" 2>/dev/null; then
    HAS_LOG_BIFENTHRIN="true"
fi

HAS_LOG_SPRAYER="false"
if grep -q "sprayer decontamination" "$DUMP_LOWER" 2>/dev/null; then
    HAS_LOG_SPRAYER="true"
fi

# --- Log types ---
HAS_TYPE_OBSERVATION="false"
if grep -q "observation" "$DUMP_LOWER" 2>/dev/null; then
    HAS_TYPE_OBSERVATION="true"
fi

HAS_TYPE_INPUT="false"
if grep -q "input" "$DUMP_LOWER" 2>/dev/null; then
    HAS_TYPE_INPUT="true"
fi

HAS_TYPE_ACTIVITY="false"
if grep -q "activity" "$DUMP_LOWER" 2>/dev/null; then
    HAS_TYPE_ACTIVITY="true"
fi

# --- Key phrases from notes ---
HAS_PHRASE_NODE_INJURY="false"
if grep -q "node-injury" "$DUMP_LOWER" 2>/dev/null; then
    HAS_PHRASE_NODE_INJURY="true"
fi

HAS_PHRASE_EPA_REG="false"
if grep -q "279-3206" "$DUMP_LOWER" 2>/dev/null; then
    HAS_PHRASE_EPA_REG="true"
fi

HAS_PHRASE_TEEJET="false"
if grep -q "teejet" "$DUMP_LOWER" 2>/dev/null; then
    HAS_PHRASE_TEEJET="true"
fi

HAS_PHRASE_ROOTWORM="false"
if grep -q "rootworm" "$DUMP_LOWER" 2>/dev/null; then
    HAS_PHRASE_ROOTWORM="true"
fi

HAS_PHRASE_BIFENTHRIN="false"
if grep -q "bifenthrin" "$DUMP_LOWER" 2>/dev/null; then
    HAS_PHRASE_BIFENTHRIN="true"
fi

HAS_PHRASE_TRIPLE_RINSE="false"
if grep -q "triple rinse" "$DUMP_LOWER" 2>/dev/null; then
    HAS_PHRASE_TRIPLE_RINSE="true"
fi

# --- Edit step: appended text ---
HAS_EDIT_APPEND="false"
if grep -q "treatment applied" "$DUMP_LOWER" 2>/dev/null; then
    HAS_EDIT_APPEND="true"
fi

# --- Server config ---
HAS_SERVER_URL="false"
if grep -q "cropguard.iastate.edu" "$DUMP_LOWER" 2>/dev/null; then
    HAS_SERVER_URL="true"
fi

HAS_USERNAME="false"
if grep -q "j.hansen" "$DUMP_LOWER" 2>/dev/null; then
    HAS_USERNAME="true"
fi

# --- Date ---
HAS_DATE="false"
if grep -q "2025-10-08\|2025/10/08\|10/08/2025\|08.*oct.*2025\|oct.*08.*2025\|oct.*8.*2025" "$DUMP_LOWER" 2>/dev/null; then
    HAS_DATE="true"
fi

# --- App foreground check ---
FOCUSED_ACTIVITY=$(dumpsys activity activities 2>/dev/null | grep "mResumedActivity" | head -1)
APP_IN_FOREGROUND="false"
if echo "$FOCUSED_ACTIVITY" | grep -q "$PACKAGE"; then
    APP_IN_FOREGROUND="true"
fi

# ---------------------------------------------------------------------------
# 6. Create result JSON
# ---------------------------------------------------------------------------
cat > /sdcard/task_result_spray_audit.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_in_foreground": $APP_IN_FOREGROUND,
    "ui_dump_exists": $UI_DUMP_EXISTS,
    "ui_dump_size": $UI_DUMP_SIZE,
    "data_dump_size": $DUMP_SIZE,
    "logs_found": {
        "rootworm_log": $HAS_LOG_ROOTWORM,
        "bifenthrin_log": $HAS_LOG_BIFENTHRIN,
        "sprayer_log": $HAS_LOG_SPRAYER,
        "type_observation": $HAS_TYPE_OBSERVATION,
        "type_input": $HAS_TYPE_INPUT,
        "type_activity": $HAS_TYPE_ACTIVITY
    },
    "notes_phrases": {
        "node_injury": $HAS_PHRASE_NODE_INJURY,
        "epa_reg": $HAS_PHRASE_EPA_REG,
        "teejet": $HAS_PHRASE_TEEJET,
        "rootworm": $HAS_PHRASE_ROOTWORM,
        "bifenthrin": $HAS_PHRASE_BIFENTHRIN,
        "triple_rinse": $HAS_PHRASE_TRIPLE_RINSE
    },
    "edit_step": {
        "treatment_applied": $HAS_EDIT_APPEND
    },
    "server_config": {
        "url_found": $HAS_SERVER_URL,
        "username_found": $HAS_USERNAME
    },
    "date_found": $HAS_DATE,
    "screenshot_path": "/sdcard/final_screenshot_spray_audit.png",
    "ui_dump_path": "/sdcard/ui_dump_spray_audit.xml"
}
EOF

chmod 666 /sdcard/task_result_spray_audit.json 2>/dev/null || true
chmod 666 /sdcard/final_screenshot_spray_audit.png 2>/dev/null || true
chmod 666 /sdcard/ui_dump_spray_audit.xml 2>/dev/null || true

echo "Result saved to /sdcard/task_result_spray_audit.json"
cat /sdcard/task_result_spray_audit.json
echo "=== Export complete ==="
