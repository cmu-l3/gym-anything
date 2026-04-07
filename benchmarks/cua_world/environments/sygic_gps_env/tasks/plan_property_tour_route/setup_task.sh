#!/system/bin/sh
# Setup script for plan_property_tour_route task.
# Clears Home/Work/Favorites, sets wrong baseline for route and view settings.
#
# Baseline state:
#   - Home/Work cleared (no entries in place table type 0,1)
#   - Favorites cleared
#   - Route compute = Fastest ("1") — agent must change to Shortest ("0")
#   - Arrive-in-direction = false — agent must enable
#   - Color scheme = Auto ("0") — agent must change to Night ("2")

# Ensure root access
if [ "$(id -u)" != "0" ]; then
    exec su 0 sh "$0" "$@"
fi

echo "=== Setting up plan_property_tour_route task ==="

PACKAGE="com.sygic.aura"
DB_PATH="/data/data/$PACKAGE/databases/places-database"
PREFS_FILE="/data/data/$PACKAGE/shared_prefs/com.sygic.aura_preferences.xml"

# Force stop to get clean state
am force-stop $PACKAGE
sleep 2

# --- Clear existing Home, Work, Favorites (Lesson 177: targeted cleanup) ---
if [ -f "$DB_PATH" ]; then
    echo "Clearing Home/Work entries..."
    sqlite3 "$DB_PATH" "DELETE FROM place WHERE type IN (0, 1);" 2>/dev/null
    echo "Clearing favorites..."
    sqlite3 "$DB_PATH" "DELETE FROM favorites;" 2>/dev/null
    echo "Database cleaned."
fi

# Record baseline counts after cleanup
PLACE_COUNT=0
FAVORITES_COUNT=0
if [ -f "$DB_PATH" ]; then
    PLACE_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM place;" 2>/dev/null || echo "0")
    FAVORITES_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM favorites;" 2>/dev/null || echo "0")
fi

# --- Set route compute to Fastest ("1") — agent must change to Shortest ("0") ---
sed -i 's/name="preferenceKey_routePlanning_routeComputing">[^<]*/name="preferenceKey_routePlanning_routeComputing">1/' "$PREFS_FILE"

# --- Set arrive-in-direction to false — agent must enable ---
sed -i 's/name="preferenceKey_arriveInDrivingSide" value="[^"]*"/name="preferenceKey_arriveInDrivingSide" value="false"/' "$PREFS_FILE"

# --- Set color scheme to Auto ("0") — agent must change to Night ("2") ---
sed -i 's/name="preferenceKey_colorScheme">[^<]*/name="preferenceKey_colorScheme">0/' "$PREFS_FILE"

# Record baseline
cat > /data/local/tmp/plan_property_tour_route_baseline.json << ENDJSON
{
    "baseline_place_count": $PLACE_COUNT,
    "baseline_favorites_count": $FAVORITES_COUNT,
    "baseline_route_compute": "1",
    "baseline_arrive_in_dir": "false",
    "baseline_color_scheme": "0"
}
ENDJSON

# Record timestamp
date +%s > /data/local/tmp/plan_property_tour_route_start_ts

# Press Home
input keyevent KEYCODE_HOME
sleep 1

# Launch app
echo "Launching Sygic GPS Navigation..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 12

CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher"; then
    echo "App not in foreground, relaunching..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 10
fi

screencap -p /data/local/tmp/plan_property_start_screenshot.png 2>/dev/null

echo "=== plan_property_tour_route task setup complete ==="
