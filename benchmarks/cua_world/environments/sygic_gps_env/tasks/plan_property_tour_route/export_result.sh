#!/system/bin/sh
# Export script for plan_property_tour_route task.
#
# Result JSON fields (contract with verifier.py):
#   home                    object|null — Home place entry
#   work                    object|null — Work place entry
#   favorites               array       — Favorites list
#   favorites_count         int
#   place_count             int
#   baseline_place_count    int
#   baseline_favorites_count int
#   route_compute           string
#   arrive_in_direction     string
#   color_scheme            string
#   baseline_route_compute  string
#   baseline_color_scheme   string

# Ensure root access
if [ "$(id -u)" != "0" ]; then
    exec su 0 sh "$0" "$@"
fi

echo "=== Exporting plan_property_tour_route result ==="

PACKAGE="com.sygic.aura"
DB_PATH="/data/data/$PACKAGE/databases/places-database"
PREFS_FILE="/data/data/$PACKAGE/shared_prefs/com.sygic.aura_preferences.xml"
RESULT_FILE="/data/local/tmp/plan_property_tour_route_result.json"

# Take screenshot
screencap -p /data/local/tmp/plan_property_end_screenshot.png 2>/dev/null
uiautomator dump /sdcard/ui_dump.xml 2>/dev/null

# Force stop app so DB writes flush
am force-stop $PACKAGE
sleep 3

# --- Query places database ---
if [ ! -f "$DB_PATH" ]; then
    cat > "$RESULT_FILE" << 'ENDJSON'
{
  "error": "places-database not found",
  "home": null, "work": null, "favorites": [],
  "favorites_count": 0, "place_count": 0,
  "baseline_place_count": 0, "baseline_favorites_count": 0,
  "route_compute": "", "arrive_in_direction": "",
  "color_scheme": "", "baseline_route_compute": "1",
  "baseline_color_scheme": "0"
}
ENDJSON
    exit 0
fi

# Query Home (type=0)
HOME_ROW=$(sqlite3 "$DB_PATH" "SELECT id, title, latitude, longitude, address_street, address_city, address_iso FROM place WHERE type=0 LIMIT 1;" 2>/dev/null)
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

# Query Work (type=1)
WORK_ROW=$(sqlite3 "$DB_PATH" "SELECT id, title, latitude, longitude, address_street, address_city, address_iso FROM place WHERE type=1 LIMIT 1;" 2>/dev/null)
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

# Query favorites
FAVORITES_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM favorites;" 2>/dev/null || echo "0")
PLACE_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM place;" 2>/dev/null || echo "0")

# Build favorites array
sqlite3 "$DB_PATH" "SELECT id, title, latitude, longitude, address_street, address_city FROM favorites LIMIT 20;" 2>/dev/null | while IFS='|' read -r FID FTITLE FLAT FLON FSTREET FCITY; do
    printf "{\"id\": \"%s\", \"title\": \"%s\", \"latitude\": %s, \"longitude\": %s, \"street\": \"%s\", \"city\": \"%s\"}," "$FID" "$FTITLE" "$FLAT" "$FLON" "$FSTREET" "$FCITY"
done > /data/local/tmp/_ppt_fav_entries.json

FAV_ENTRIES=$(cat /data/local/tmp/_ppt_fav_entries.json 2>/dev/null | sed 's/,$//')
FAVORITES_JSON="[$FAV_ENTRIES]"

# Query preferences
ROUTE_COMPUTE=$(grep 'preferenceKey_routePlanning_routeComputing' "$PREFS_FILE" 2>/dev/null | sed 's/.*>\(.*\)<.*/\1/')
[ -z "$ROUTE_COMPUTE" ] && ROUTE_COMPUTE=""

ARRIVE_IN_DIR=$(grep 'preferenceKey_arriveInDrivingSide' "$PREFS_FILE" 2>/dev/null | sed 's/.*value="\([^"]*\)".*/\1/')
[ -z "$ARRIVE_IN_DIR" ] && ARRIVE_IN_DIR=""

COLOR_SCHEME=$(grep 'preferenceKey_colorScheme' "$PREFS_FILE" 2>/dev/null | sed 's/.*>\(.*\)<.*/\1/')
[ -z "$COLOR_SCHEME" ] && COLOR_SCHEME=""

# Read baseline
BASELINE_PLACE=$(grep baseline_place_count /data/local/tmp/plan_property_tour_route_baseline.json 2>/dev/null | tr -dc '0-9')
BASELINE_FAV=$(grep baseline_favorites_count /data/local/tmp/plan_property_tour_route_baseline.json 2>/dev/null | tr -dc '0-9')
[ -z "$BASELINE_PLACE" ] && BASELINE_PLACE=0
[ -z "$BASELINE_FAV" ] && BASELINE_FAV=0

# Write result
cat > "$RESULT_FILE" << ENDJSON
{
  "home": $HOME_JSON,
  "work": $WORK_JSON,
  "favorites": $FAVORITES_JSON,
  "favorites_count": $FAVORITES_COUNT,
  "place_count": $PLACE_COUNT,
  "baseline_place_count": $BASELINE_PLACE,
  "baseline_favorites_count": $BASELINE_FAV,
  "route_compute": "$ROUTE_COMPUTE",
  "arrive_in_direction": "$ARRIVE_IN_DIR",
  "color_scheme": "$COLOR_SCHEME",
  "baseline_route_compute": "1",
  "baseline_color_scheme": "0",
  "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

echo "Result JSON:"
cat "$RESULT_FILE"

echo "=== Export Complete ==="
