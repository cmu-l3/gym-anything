#!/system/bin/sh
echo "=== Exporting Digitize Grid Intersections result ==="

# Define paths
DEST_GPKG="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets/world_survey.gpkg"
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /sdcard/initial_count.txt 2>/dev/null || echo "0")

# 1. Check if file was modified
FILE_MODIFIED="false"
if [ -f "$DEST_GPKG" ]; then
    MTIME=$(stat -c %Y "$DEST_GPKG" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 2. Extract Data using sqlite3
# We extract name, notes, and the raw geometry blob (in hex) to parse in python
# We filter for features created/modified (conceptually, though here we just grab by name matches)
# We can't easily parse WKB in shell, so we dump the hex string.

echo "Querying GeoPackage..."

# extraction format: name|notes|hex(geom)
DATA_DUMP=$(sqlite3 "$DEST_GPKG" "SELECT name, notes, hex(geom) FROM field_observations WHERE name LIKE 'Station_%';" 2>/dev/null)

FINAL_COUNT=$(sqlite3 "$DEST_GPKG" "SELECT COUNT(*) FROM field_observations;" 2>/dev/null || echo "0")

# 3. Create JSON result
# We construct the JSON manually in shell
JSON_PATH="/sdcard/task_result.json"

echo "{" > "$JSON_PATH"
echo "  \"file_modified\": $FILE_MODIFIED," >> "$JSON_PATH"
echo "  \"initial_count\": $INITIAL_COUNT," >> "$JSON_PATH"
echo "  \"final_count\": $FINAL_COUNT," >> "$JSON_PATH"
echo "  \"features\": [" >> "$JSON_PATH"

FIRST=1
# Read line by line
echo "$DATA_DUMP" | while read -r line; do
    if [ -n "$line" ]; then
        if [ "$FIRST" -eq 0 ]; then echo "," >> "$JSON_PATH"; fi
        
        # Escape quotes in strings
        NAME=$(echo "$line" | cut -d'|' -f1 | sed 's/"/\\"/g')
        NOTES=$(echo "$line" | cut -d'|' -f2 | sed 's/"/\\"/g')
        GEOM_HEX=$(echo "$line" | cut -d'|' -f3)
        
        echo "    {" >> "$JSON_PATH"
        echo "      \"name\": \"$NAME\"," >> "$JSON_PATH"
        echo "      \"notes\": \"$NOTES\"," >> "$JSON_PATH"
        echo "      \"geom_hex\": \"$GEOM_HEX\"" >> "$JSON_PATH"
        echo "    }" >> "$JSON_PATH"
        FIRST=0
    fi
done

echo "  ]" >> "$JSON_PATH"
echo "}" >> "$JSON_PATH"

echo "Result exported to $JSON_PATH"
chmod 666 "$JSON_PATH"