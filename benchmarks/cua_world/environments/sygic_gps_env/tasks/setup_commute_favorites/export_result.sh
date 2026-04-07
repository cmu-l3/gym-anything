#!/system/bin/sh
# Post-task hook: Export places database state for verification.
# Queries the SQLite database for Home, Work, and Favorites entries
# and writes a structured JSON result file.

# Ensure root access for reading app private data
if [ "$(id -u)" != "0" ]; then
    exec su 0 sh "$0" "$@"
fi

echo "=== Exporting setup_commute_favorites result ==="

PACKAGE="com.sygic.aura"
DB_PATH="/data/data/com.sygic.aura/databases/places-database"
RESULT_FILE="/data/local/tmp/setup_commute_favorites_result.json"
BASELINE_FILE="/data/local/tmp/setup_commute_favorites_baseline.json"

# Force stop the app so DB writes are flushed
am force-stop $PACKAGE
sleep 3

# Take screenshot for reference
screencap -p /sdcard/final_screenshot.png 2>/dev/null
echo "Screenshot captured to /sdcard/final_screenshot.png"

# Dump UI hierarchy
uiautomator dump /sdcard/ui_dump.xml 2>/dev/null

# Initialize result
if [ ! -f "$DB_PATH" ]; then
    echo "ERROR: places-database not found!"
    cat > "$RESULT_FILE" << 'ENDJSON'
{
  "error": "places-database not found",
  "home": null,
  "work": null,
  "favorites": [],
  "favorites_count": 0
}
ENDJSON
    echo "=== Export completed (with error) ==="
    exit 0
fi

# Query Home entry (type=0) from place table
HOME_ROW=$(sqlite3 "$DB_PATH" "SELECT id, title, latitude, longitude, address_street, address_city, address_iso FROM place WHERE type=0 LIMIT 1;" 2>/dev/null)
# Query Work entry (type=1) from place table
WORK_ROW=$(sqlite3 "$DB_PATH" "SELECT id, title, latitude, longitude, address_street, address_city, address_iso FROM place WHERE type=1 LIMIT 1;" 2>/dev/null)
# Query all favorites
FAVORITES_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM favorites;" 2>/dev/null || echo "0")
# Query total place count
PLACE_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM place;" 2>/dev/null || echo "0")

# Parse Home data
if [ -n "$HOME_ROW" ]; then
    HOME_ID=$(echo "$HOME_ROW" | cut -d'|' -f1)
    HOME_TITLE=$(echo "$HOME_ROW" | cut -d'|' -f2)
    HOME_LAT=$(echo "$HOME_ROW" | cut -d'|' -f3)
    HOME_LON=$(echo "$HOME_ROW" | cut -d'|' -f4)
    HOME_STREET=$(echo "$HOME_ROW" | cut -d'|' -f5)
    HOME_CITY=$(echo "$HOME_ROW" | cut -d'|' -f6)
    HOME_ISO=$(echo "$HOME_ROW" | cut -d'|' -f7)
    HOME_JSON="{\"id\": \"$HOME_ID\", \"title\": \"$HOME_TITLE\", \"latitude\": $HOME_LAT, \"longitude\": $HOME_LON, \"street\": \"$HOME_STREET\", \"city\": \"$HOME_CITY\", \"iso\": \"$HOME_ISO\"}"
else
    HOME_JSON="null"
fi

# Parse Work data
if [ -n "$WORK_ROW" ]; then
    WORK_ID=$(echo "$WORK_ROW" | cut -d'|' -f1)
    WORK_TITLE=$(echo "$WORK_ROW" | cut -d'|' -f2)
    WORK_LAT=$(echo "$WORK_ROW" | cut -d'|' -f3)
    WORK_LON=$(echo "$WORK_ROW" | cut -d'|' -f4)
    WORK_STREET=$(echo "$WORK_ROW" | cut -d'|' -f5)
    WORK_CITY=$(echo "$WORK_ROW" | cut -d'|' -f6)
    WORK_ISO=$(echo "$WORK_ROW" | cut -d'|' -f7)
    WORK_JSON="{\"id\": \"$WORK_ID\", \"title\": \"$WORK_TITLE\", \"latitude\": $WORK_LAT, \"longitude\": $WORK_LON, \"street\": \"$WORK_STREET\", \"city\": \"$WORK_CITY\", \"iso\": \"$WORK_ISO\"}"
else
    WORK_JSON="null"
fi

# Query favorites details (up to 20)
FAVORITES_JSON="["
FIRST=1
sqlite3 "$DB_PATH" "SELECT id, title, latitude, longitude, address_street, address_city FROM favorites LIMIT 20;" 2>/dev/null | while IFS='|' read -r FID FTITLE FLAT FLON FSTREET FCITY; do
    if [ "$FIRST" = "1" ]; then
        FIRST=0
    else
        printf ","
    fi
    printf "{\"id\": \"%s\", \"title\": \"%s\", \"latitude\": %s, \"longitude\": %s, \"street\": \"%s\", \"city\": \"%s\"}" "$FID" "$FTITLE" "$FLAT" "$FLON" "$FSTREET" "$FCITY"
done > /data/local/tmp/_fav_entries.json

FAV_ENTRIES=$(cat /data/local/tmp/_fav_entries.json 2>/dev/null)
FAVORITES_JSON="[$FAV_ENTRIES]"

# Read baseline
BASELINE_PLACE=0
BASELINE_FAV=0
if [ -f "$BASELINE_FILE" ]; then
    # Simple parsing of baseline values
    BASELINE_PLACE=$(grep baseline_place_count "$BASELINE_FILE" | tr -dc '0-9')
    BASELINE_FAV=$(grep baseline_favorites_count "$BASELINE_FILE" | tr -dc '0-9')
fi

# Write result JSON
cat > "$RESULT_FILE" << ENDJSON
{
  "home": $HOME_JSON,
  "work": $WORK_JSON,
  "favorites": $FAVORITES_JSON,
  "favorites_count": $FAVORITES_COUNT,
  "place_count": $PLACE_COUNT,
  "baseline_place_count": $BASELINE_PLACE,
  "baseline_favorites_count": $BASELINE_FAV
}
ENDJSON

echo "Result written to $RESULT_FILE"
echo "Home: $HOME_JSON"
echo "Work: $WORK_JSON"
echo "Favorites count: $FAVORITES_COUNT"

echo "=== Export completed ==="
