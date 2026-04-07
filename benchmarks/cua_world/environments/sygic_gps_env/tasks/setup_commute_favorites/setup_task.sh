#!/system/bin/sh
# Setup script for setup_commute_favorites task.
# Clears existing Home/Work/Favorites data, records baseline counts, then launches the app.

# Ensure root access for reading/writing app private data
if [ "$(id -u)" != "0" ]; then
    exec su 0 sh "$0" "$@"
fi

echo "=== Setting up setup_commute_favorites task ==="

PACKAGE="com.sygic.aura"
DB_PATH="/data/data/com.sygic.aura/databases/places-database"
BASELINE="/data/local/tmp/setup_commute_favorites_baseline.json"

# Force stop to get clean state
am force-stop $PACKAGE
sleep 2

# Clear existing Home, Work, and Favorites data so the agent starts fresh
if [ -f "$DB_PATH" ]; then
    echo "Clearing existing place entries (Home/Work)..."
    sqlite3 "$DB_PATH" "DELETE FROM place WHERE type IN (0, 1);" 2>/dev/null
    echo "Clearing existing favorites..."
    sqlite3 "$DB_PATH" "DELETE FROM favorites;" 2>/dev/null
    echo "Database cleaned."
else
    echo "Warning: places-database not found at $DB_PATH. App may not have been initialized yet."
fi

# Record baseline counts after cleanup
PLACE_COUNT=0
FAVORITES_COUNT=0
if [ -f "$DB_PATH" ]; then
    PLACE_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM place;" 2>/dev/null || echo "0")
    FAVORITES_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM favorites;" 2>/dev/null || echo "0")
fi

# Record setup timestamp
SETUP_TIME=$(date +%s)

# Write baseline JSON
cat > "$BASELINE" << ENDJSON
{
  "setup_timestamp": $SETUP_TIME,
  "baseline_place_count": $PLACE_COUNT,
  "baseline_favorites_count": $FAVORITES_COUNT
}
ENDJSON

echo "Baseline recorded: place_count=$PLACE_COUNT, favorites_count=$FAVORITES_COUNT"

# Press Home first
input keyevent KEYCODE_HOME
sleep 1

# Launch app
echo "Launching Sygic GPS Navigation..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 12

# Verify app is in foreground
CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher"; then
    echo "App not in foreground, relaunching..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 10
fi

echo "=== setup_commute_favorites task setup complete ==="
echo "App should be on main map screen. Agent should use the search feature to set Home, Work, and add a Gas Station favorite."
