#!/system/bin/sh
# Post-task hook: Export current preference values for verification.
# Force-stops the app first so in-memory prefs are flushed to XML on disk,
# then reads each relevant preference and writes a JSON result file.

# Ensure root access for reading app private data
if [ "$(id -u)" != "0" ]; then
    exec su 0 sh "$0" "$@"
fi

echo "=== Exporting prepare_international_trip result ==="

PACKAGE="com.sygic.aura"
PREFS_FILE="/data/data/$PACKAGE/shared_prefs/com.sygic.aura_preferences.xml"

# Take final screenshot
screencap -p /data/local/tmp/task_end_screenshot.png 2>/dev/null
echo "Final screenshot captured."

# Dump UI hierarchy
uiautomator dump /sdcard/ui_dump.xml 2>/dev/null

# Force stop so preferences are flushed to disk
am force-stop $PACKAGE
sleep 2

# --- Read current values of all 5 settings ---

DISTANCE_UNITS=$(grep 'preferenceKey_regional_distanceUnitsFormat' "$PREFS_FILE" | sed 's/.*>\([^<]*\)<.*/\1/')
TEMPERATURE_UNITS=$(grep 'preferenceKey_weather_temperatureUnits' "$PREFS_FILE" | sed 's/.*>\([^<]*\)<.*/\1/')
GPS_FORMAT=$(grep 'preferenceKey_regional_gpsFormat' "$PREFS_FILE" | sed 's/.*>\([^<]*\)<.*/\1/')
TIME_FORMAT=$(grep 'preferenceKey_regional_timeFormat' "$PREFS_FILE" | sed 's/.*>\([^<]*\)<.*/\1/')
COLOR_SCHEME=$(grep 'preferenceKey_app_theme' "$PREFS_FILE" | sed 's/.*>\([^<]*\)<.*/\1/')

# --- Read baseline values recorded during setup ---

BASELINE_DISTANCE=$(cat /data/local/tmp/baseline_distance_units 2>/dev/null || echo "1")
BASELINE_TEMP=$(cat /data/local/tmp/baseline_temperature_units 2>/dev/null || echo "Metric")
BASELINE_GPS=$(cat /data/local/tmp/baseline_gps_format 2>/dev/null || echo "0")
BASELINE_TIME=$(cat /data/local/tmp/baseline_time_format 2>/dev/null || echo "0")
BASELINE_THEME=$(cat /data/local/tmp/baseline_color_scheme 2>/dev/null || echo "0")

# --- Write result JSON ---

cat > /data/local/tmp/prepare_international_trip_result.json << ENDOFRESULT
{
    "distance_units": "$DISTANCE_UNITS",
    "temperature_units": "$TEMPERATURE_UNITS",
    "gps_format": "$GPS_FORMAT",
    "time_format": "$TIME_FORMAT",
    "color_scheme": "$COLOR_SCHEME",
    "baseline_distance_units": "$BASELINE_DISTANCE",
    "baseline_temperature_units": "$BASELINE_TEMP",
    "baseline_gps_format": "$BASELINE_GPS",
    "baseline_time_format": "$BASELINE_TIME",
    "baseline_color_scheme": "$BASELINE_THEME",
    "export_timestamp": "$(date -Iseconds)"
}
ENDOFRESULT

echo "Result JSON:"
cat /data/local/tmp/prepare_international_trip_result.json

echo "=== Export complete ==="
