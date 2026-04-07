#!/system/bin/sh
# Post-task hook for optimize_highway_navigation.
# Force stops the app to flush preferences, then reads each preference
# value from the shared_prefs XML and writes a JSON result file.

# Ensure root access for reading app private data
if [ "$(id -u)" != "0" ]; then
    exec su 0 sh "$0" "$@"
fi

echo "=== Exporting optimize_highway_navigation result ==="

PACKAGE="com.sygic.aura"
PREFS_FILE="/data/data/$PACKAGE/shared_prefs/com.sygic.aura_preferences.xml"
RESULT_FILE="/data/local/tmp/optimize_highway_navigation_result.json"

# Take final screenshot
screencap -p /data/local/tmp/task_end_screenshot.png 2>/dev/null

# Dump UI hierarchy
uiautomator dump /sdcard/ui_dump.xml 2>/dev/null

# Force stop app so all preference writes are flushed to disk
am force-stop $PACKAGE
sleep 2

# --- Read each preference value ---

# Route avoidances (boolean values)
AVOID_HIGHWAYS=$(grep 'tmp_preferenceKey_routePlanning_motorways_avoid' "$PREFS_FILE" | sed 's/.*value="\([^"]*\)".*/\1/')
AVOID_TOLL_ROADS=$(grep 'tmp_preferenceKey_routePlanning_tollRoads_avoid' "$PREFS_FILE" | sed 's/.*value="\([^"]*\)".*/\1/')
AVOID_UNPAVED=$(grep 'tmp_preferenceKey_routePlanning_unpavedRoads_avoid' "$PREFS_FILE" | sed 's/.*value="\([^"]*\)".*/\1/')

# Route compute (string value between tags)
ROUTE_COMPUTE=$(grep 'preferenceKey_routePlanning_routeComputing' "$PREFS_FILE" | sed 's/.*>\(.*\)<.*/\1/')

# Compass (boolean)
COMPASS=$(grep 'preferenceKey_navigation_compassAlwaysOn' "$PREFS_FILE" | sed 's/.*value="\([^"]*\)".*/\1/')

# Driving mode (string value between tags)
DRIVING_MODE=$(grep 'preferenceKey_drivingMode' "$PREFS_FILE" | sed 's/.*>\(.*\)<.*/\1/')

# 3D terrain (boolean)
TERRAIN_3D=$(grep 'preferenceKey_map_3dTerrain' "$PREFS_FILE" | sed 's/.*value="\([^"]*\)".*/\1/')

# Font size (string value between tags)
FONT_SIZE=$(grep 'preferenceKey_map_fontSize' "$PREFS_FILE" | sed 's/.*>\(.*\)<.*/\1/')

# Read baseline values saved by setup
BASELINE_ROUTE_COMPUTE=$(cat /data/local/tmp/baseline_route_compute 2>/dev/null || echo "0")
BASELINE_DRIVING_MODE=$(cat /data/local/tmp/baseline_driving_mode 2>/dev/null || echo "1")

# --- Build result JSON ---
cat > "$RESULT_FILE" << ENDOFRESULT
{
    "avoid_highways": "${AVOID_HIGHWAYS:-unknown}",
    "avoid_toll_roads": "${AVOID_TOLL_ROADS:-unknown}",
    "avoid_unpaved_roads": "${AVOID_UNPAVED:-unknown}",
    "route_compute": "${ROUTE_COMPUTE:-unknown}",
    "compass_always_on": "${COMPASS:-unknown}",
    "driving_mode": "${DRIVING_MODE:-unknown}",
    "terrain_3d": "${TERRAIN_3D:-unknown}",
    "font_size": "${FONT_SIZE:-unknown}",
    "baseline_route_compute": "${BASELINE_ROUTE_COMPUTE}",
    "baseline_driving_mode": "${BASELINE_DRIVING_MODE}",
    "export_timestamp": "$(date -Iseconds)"
}
ENDOFRESULT

echo "Result JSON:"
cat "$RESULT_FILE"

echo "=== Export Complete ==="
