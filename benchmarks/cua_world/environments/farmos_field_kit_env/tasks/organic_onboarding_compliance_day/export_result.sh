#!/system/bin/sh
# Post-task hook: Export farmOS state for organic_onboarding_compliance_day verification.
# Collects: UI hierarchy, app data dump, screenshot, and structured result JSON.

echo "=== Exporting organic_onboarding_compliance_day state ==="

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
screencap -p /sdcard/final_screenshot_onboarding.png 2>/dev/null

# ---------------------------------------------------------------------------
# 3. Dump UI hierarchy (Tasks list should be visible)
# ---------------------------------------------------------------------------
rm -f /sdcard/ui_dump_onboarding.xml 2>/dev/null
uiautomator dump /sdcard/ui_dump_onboarding.xml > /dev/null 2>&1

UI_DUMP_EXISTS="false"
UI_DUMP_SIZE=0
if [ -f /sdcard/ui_dump_onboarding.xml ]; then
    UI_DUMP_EXISTS="true"
    UI_DUMP_SIZE=$(stat -c %s /sdcard/ui_dump_onboarding.xml 2>/dev/null || echo "0")
fi

# ---------------------------------------------------------------------------
# 4. Dump app internal data (IndexedDB/LevelDB/SQLite strings)
# ---------------------------------------------------------------------------
DATA_DUMP="/data/local/tmp/app_data_dump_onboarding.txt"
> "$DATA_DUMP"

echo "Dumping app data strings..."
find /data/data/$PACKAGE/ -type f \( -name "*.ldb" -o -name "*.log" -o -name "*.db" -o -name "*.sqlite" -o -name "00000*" \) 2>/dev/null | while read f; do
    strings "$f" 2>/dev/null >> "$DATA_DUMP"
done

# Also check SharedPreferences
find /data/data/$PACKAGE/shared_prefs/ -name "*.xml" 2>/dev/null | while read f; do
    cat "$f" 2>/dev/null >> "$DATA_DUMP"
done

DUMP_SIZE=$(stat -c %s "$DATA_DUMP" 2>/dev/null || echo "0")

# Create lowercase copy for case-insensitive searches
DUMP_LOWER="/data/local/tmp/app_data_dump_onboarding_lower.txt"
if [ -s "$DATA_DUMP" ]; then
    cat "$DATA_DUMP" | tr 'A-Z' 'a-z' > "$DUMP_LOWER" 2>/dev/null || true
else
    > "$DUMP_LOWER"
fi

# ---------------------------------------------------------------------------
# 5. Check for specific content in dumped data
# ---------------------------------------------------------------------------

# --- Server config ---
HAS_SERVER_URL="false"
if grep -q "fieldops.stateu.edu" "$DUMP_LOWER" 2>/dev/null; then
    HAS_SERVER_URL="true"
fi

HAS_USERNAME="false"
if grep -q "tech_hansen" "$DUMP_LOWER" 2>/dev/null; then
    HAS_USERNAME="true"
fi

# --- Log names ---
HAS_LOG_BURNDOWN="false"
if grep -q "fall burndown" "$DUMP_LOWER" 2>/dev/null; then
    HAS_LOG_BURNDOWN="true"
fi

HAS_LOG_DRIFT="false"
if grep -q "drift check" "$DUMP_LOWER" 2>/dev/null; then
    HAS_LOG_DRIFT="true"
fi

# --- Log types ---
HAS_TYPE_INPUT="false"
if grep -q "input" "$DUMP_LOWER" 2>/dev/null; then
    HAS_TYPE_INPUT="true"
fi

HAS_TYPE_OBSERVATION="false"
if grep -q "observation" "$DUMP_LOWER" 2>/dev/null; then
    HAS_TYPE_OBSERVATION="true"
fi

# --- Key phrases from notes ---
HAS_PHRASE_ROUNDUP="false"
if grep -q "roundup powermax" "$DUMP_LOWER" 2>/dev/null; then
    HAS_PHRASE_ROUNDUP="true"
fi

HAS_PHRASE_BUFFER="false"
if grep -q "buffer zones" "$DUMP_LOWER" 2>/dev/null; then
    HAS_PHRASE_BUFFER="true"
fi

HAS_PHRASE_BURNDOWN="false"
if grep -q "burndown" "$DUMP_LOWER" 2>/dev/null; then
    HAS_PHRASE_BURNDOWN="true"
fi

HAS_PHRASE_DRIFT="false"
if grep -q "downwind" "$DUMP_LOWER" 2>/dev/null; then
    HAS_PHRASE_DRIFT="true"
fi

HAS_PHRASE_RESIDUE="false"
if grep -q "crop residue" "$DUMP_LOWER" 2>/dev/null; then
    HAS_PHRASE_RESIDUE="true"
fi

# --- Edit step: appended text ---
HAS_EDIT_APPEND="false"
if grep -q "county ag office" "$DUMP_LOWER" 2>/dev/null; then
    HAS_EDIT_APPEND="true"
fi

# --- Quantity values ---
HAS_QTY_32="false"
if grep -q '"32"\|:32,' "$DATA_DUMP" 2>/dev/null; then
    HAS_QTY_32="true"
fi

HAS_QTY_8_5="false"
if grep -q '8\.5\|8.5' "$DATA_DUMP" 2>/dev/null; then
    HAS_QTY_8_5="true"
fi

HAS_QTY_22="false"
if grep -q '"22"\|:22,' "$DATA_DUMP" 2>/dev/null; then
    HAS_QTY_22="true"
fi

HAS_QTY_150="false"
if grep -q '"150"\|:150,' "$DATA_DUMP" 2>/dev/null; then
    HAS_QTY_150="true"
fi

# --- Quantity labels ---
HAS_LABEL_HERBICIDE="false"
if grep -q "herbicide rate" "$DUMP_LOWER" 2>/dev/null; then
    HAS_LABEL_HERBICIDE="true"
fi

HAS_LABEL_AMS="false"
if grep -q "ams rate" "$DUMP_LOWER" 2>/dev/null; then
    HAS_LABEL_AMS="true"
fi

HAS_LABEL_ACRES="false"
if grep -q "acres treated" "$DUMP_LOWER" 2>/dev/null; then
    HAS_LABEL_ACRES="true"
fi

HAS_LABEL_BUFFER_DIST="false"
if grep -q "buffer distance" "$DUMP_LOWER" 2>/dev/null; then
    HAS_LABEL_BUFFER_DIST="true"
fi

HAS_LABEL_ROWS="false"
if grep -q "rows inspected" "$DUMP_LOWER" 2>/dev/null; then
    HAS_LABEL_ROWS="true"
fi

# --- Date ---
HAS_DATE="false"
if grep -q "2025-10-15\|2025/10/15\|10/15/2025\|15.*oct.*2025\|oct.*15.*2025" "$DUMP_LOWER" 2>/dev/null; then
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
cat > /sdcard/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_in_foreground": $APP_IN_FOREGROUND,
    "ui_dump_exists": $UI_DUMP_EXISTS,
    "ui_dump_size": $UI_DUMP_SIZE,
    "data_dump_size": $DUMP_SIZE,
    "server_config": {
        "url_found": $HAS_SERVER_URL,
        "username_found": $HAS_USERNAME
    },
    "logs_found": {
        "burndown_log": $HAS_LOG_BURNDOWN,
        "drift_log": $HAS_LOG_DRIFT,
        "type_input": $HAS_TYPE_INPUT,
        "type_observation": $HAS_TYPE_OBSERVATION
    },
    "notes_phrases": {
        "roundup_powermax": $HAS_PHRASE_ROUNDUP,
        "buffer_zones": $HAS_PHRASE_BUFFER,
        "burndown": $HAS_PHRASE_BURNDOWN,
        "downwind_drift": $HAS_PHRASE_DRIFT,
        "crop_residue": $HAS_PHRASE_RESIDUE
    },
    "edit_step": {
        "county_ag_office": $HAS_EDIT_APPEND
    },
    "quantities": {
        "val_32": $HAS_QTY_32,
        "val_8_5": $HAS_QTY_8_5,
        "val_22": $HAS_QTY_22,
        "val_150": $HAS_QTY_150,
        "label_herbicide_rate": $HAS_LABEL_HERBICIDE,
        "label_ams_rate": $HAS_LABEL_AMS,
        "label_acres_treated": $HAS_LABEL_ACRES,
        "label_buffer_distance": $HAS_LABEL_BUFFER_DIST,
        "label_rows_inspected": $HAS_LABEL_ROWS
    },
    "date_found": $HAS_DATE,
    "screenshot_path": "/sdcard/final_screenshot_onboarding.png",
    "ui_dump_path": "/sdcard/ui_dump_onboarding.xml"
}
EOF

chmod 666 /sdcard/task_result.json 2>/dev/null || true
chmod 666 /sdcard/final_screenshot_onboarding.png 2>/dev/null || true
chmod 666 /sdcard/ui_dump_onboarding.xml 2>/dev/null || true

echo "Result saved to /sdcard/task_result.json"
cat /sdcard/task_result.json
echo "=== Export complete ==="
