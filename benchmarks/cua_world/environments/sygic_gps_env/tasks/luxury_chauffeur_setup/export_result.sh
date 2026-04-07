#!/system/bin/sh
# Post-task export for luxury_chauffeur_setup.
# Force-stops app to flush prefs, then reads each relevant preference.

if [ "$(id -u)" != "0" ]; then
    exec su 0 sh "$0" "$@"
fi

echo "=== Exporting luxury_chauffeur_setup result ==="

PACKAGE="com.sygic.aura"
PREFS_FILE="/data/data/$PACKAGE/shared_prefs/com.sygic.aura_preferences.xml"
RESULT_FILE="/data/local/tmp/luxury_chauffeur_setup_result.json"

screencap -p /data/local/tmp/luxury_chauffeur_setup_end_screenshot.png 2>/dev/null
uiautomator dump /sdcard/ui_dump_chauffeur.xml 2>/dev/null

# Force stop so preferences are flushed to disk
am force-stop $PACKAGE
sleep 2

# Read current preference values
ARRIVE_IN_DIR=$(grep 'preferenceKey_arriveInDrivingSide' "$PREFS_FILE" | sed 's/.*value="\([^"]*\)".*/\1/')
APP_THEME=$(grep 'preferenceKey_app_theme' "$PREFS_FILE" | sed 's/.*>\([^<]*\)<.*/\1/')
AVOID_TOLLS=$(grep 'tmp_preferenceKey_routePlanning_tollRoads_avoid' "$PREFS_FILE" | sed 's/.*value="\([^"]*\)".*/\1/')
COMPASS=$(grep 'preferenceKey_navigation_compassAlwaysOn' "$PREFS_FILE" | sed 's/.*value="\([^"]*\)".*/\1/')
GPS_FORMAT=$(grep 'preferenceKey_regional_gpsFormat' "$PREFS_FILE" | sed 's/.*>\([^<]*\)<.*/\1/')

# Read baselines
BASELINE_ARRIVE=$(cat /data/local/tmp/luxury_chauffeur_setup_baseline_arrive 2>/dev/null || echo "false")
BASELINE_THEME=$(cat /data/local/tmp/luxury_chauffeur_setup_baseline_theme 2>/dev/null || echo "0")
BASELINE_TOLLS=$(cat /data/local/tmp/luxury_chauffeur_setup_baseline_tolls 2>/dev/null || echo "true")
BASELINE_COMPASS=$(cat /data/local/tmp/luxury_chauffeur_setup_baseline_compass 2>/dev/null || echo "false")
BASELINE_GPS=$(cat /data/local/tmp/luxury_chauffeur_setup_baseline_gps 2>/dev/null || echo "0")

cat > "$RESULT_FILE" << ENDOFRESULT
{
    "arrive_in_direction": "$ARRIVE_IN_DIR",
    "app_theme": "$APP_THEME",
    "avoid_tolls": "$AVOID_TOLLS",
    "compass_always_on": "$COMPASS",
    "gps_format": "$GPS_FORMAT",
    "baseline_arrive": "$BASELINE_ARRIVE",
    "baseline_theme": "$BASELINE_THEME",
    "baseline_tolls": "$BASELINE_TOLLS",
    "baseline_compass": "$BASELINE_COMPASS",
    "baseline_gps": "$BASELINE_GPS",
    "export_timestamp": "$(date -Iseconds)"
}
ENDOFRESULT

echo "Result JSON:"
cat "$RESULT_FILE"
echo "=== Export complete ==="
