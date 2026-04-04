#!/system/bin/sh
# Export script for frost protection activity log task
# Runs via: adb shell sh /sdcard/tasks/record_frost_protection_activity/export_result.sh

echo "=== Exporting task results ==="

PACKAGE="org.farmos.app"
TASK_START=$(cat /data/local/tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture final screenshot
screencap -p /data/local/tmp/task_final_state.png 2>/dev/null || true

# 2. Extract Data from App Storage
# farmOS Field Kit uses IndexedDB/LevelDB/SQLite. We dump strings to find the entered text.
DATA_DUMP="/data/local/tmp/app_data_dump.txt"
> "$DATA_DUMP"

echo "Dumping app data strings..."
# Scan common storage locations for webview/hybrid apps
find /data/data/$PACKAGE/ -type f \( -name "*.ldb" -o -name "*.log" -o -name "*.db" -o -name "*.sqlite" -o -name "00000*" \) 2>/dev/null | while read f; do
    strings "$f" 2>/dev/null >> "$DATA_DUMP"
done

# Also check SharedPrefs (sometimes used for simple state)
find /data/data/$PACKAGE/shared_prefs/ -name "*.xml" 2>/dev/null | while read f; do
    cat "$f" 2>/dev/null >> "$DATA_DUMP"
done

# Convert dump to lowercase for case-insensitive searching
DUMP_LOWER="/data/local/tmp/app_data_dump_lower.txt"
if [ -s "$DATA_DUMP" ]; then
    cat "$DATA_DUMP" | tr 'A-Z' 'a-z' > "$DUMP_LOWER" 2>/dev/null || true
else
    echo "Warning: No data dumped from app storage."
fi

# 3. Check for specific content (Boolean flags)

# Date check (2024-04-18)
HAS_DATE="false"
if grep -q "2024-04-18\|2024/04/18\|18.*apr.*2024\|apr.*18.*2024" "$DUMP_LOWER"; then
    HAS_DATE="true"
fi

# Log Type check (Activity)
HAS_ACTIVITY_TYPE="false"
if grep -q "activity" "$DUMP_LOWER"; then
    HAS_ACTIVITY_TYPE="true"
fi

# Content check - specific phrases
# "Block C"
HAS_BLOCK_C="false"
if grep -q "block c" "$DUMP_LOWER"; then
    HAS_BLOCK_C="true"
fi

# "28F"
HAS_TEMP="false"
if grep -q "28f" "$DUMP_LOWER"; then
    HAS_TEMP="true"
fi

# "Emergency frost protection"
HAS_PHRASE_FROST="false"
if grep -q "emergency frost protection" "$DUMP_LOWER"; then
    HAS_PHRASE_FROST="true"
fi

# "AGRI 301"
HAS_CONTEXT="false"
if grep -q "agri 301" "$DUMP_LOWER"; then
    HAS_CONTEXT="true"
fi

# Quantity: 6
HAS_QUANTITY_VAL="false"
if grep -q "\"6\"\|:6," "$DATA_DUMP"; then
    HAS_QUANTITY_VAL="true"
fi

# Quantity Label: "Protection Duration"
HAS_QUANTITY_LABEL="false"
if grep -q "protection duration" "$DUMP_LOWER"; then
    HAS_QUANTITY_LABEL="true"
fi

# Quantity Unit: "hours"
HAS_QUANTITY_UNIT="false"
if grep -q "hours" "$DUMP_LOWER"; then
    HAS_QUANTITY_UNIT="true"
fi

# 4. Create Result JSON
TEMP_JSON="/data/local/tmp/task_result.json"
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "data_found": {
        "date": $HAS_DATE,
        "type_activity": $HAS_ACTIVITY_TYPE,
        "phrase_block_c": $HAS_BLOCK_C,
        "phrase_temp": $HAS_TEMP,
        "phrase_frost": $HAS_PHRASE_FROST,
        "phrase_context": $HAS_CONTEXT,
        "quantity_val": $HAS_QUANTITY_VAL,
        "quantity_label": $HAS_QUANTITY_LABEL,
        "quantity_unit": $HAS_QUANTITY_UNIT
    },
    "dump_size": $(stat -c %s "$DATA_DUMP" 2>/dev/null || echo "0"),
    "screenshot_path": "/data/local/tmp/task_final_state.png"
}
EOF

# Set permissions
chmod 666 "$TEMP_JSON"
chmod 666 "/data/local/tmp/task_final_state.png"

echo "Result saved to $TEMP_JSON"
cat "$TEMP_JSON"
echo "=== Export complete ==="