#!/system/bin/sh
# Setup script for prepare_international_trip task.
# Resets all View & Units settings to their defaults so the agent must change all 5.
# Records baseline values, then launches the app to the main map screen.

# Ensure root access for reading/writing app private data
if [ "$(id -u)" != "0" ]; then
    exec su 0 sh "$0" "$@"
fi

echo "=== Setting up prepare_international_trip task ==="

PACKAGE="com.sygic.aura"
PREFS_FILE="/data/data/$PACKAGE/shared_prefs/com.sygic.aura_preferences.xml"

# Force stop to get a clean state and ensure prefs are flushed to disk
am force-stop $PACKAGE
sleep 2

# --- Reset all 5 settings to their default values ---

# 1. Distance units: set to "1" (Km) — agent must change to "0" (Miles)
sed -i 's|name="preferenceKey_regional_distanceUnitsFormat">[^<]*|name="preferenceKey_regional_distanceUnitsFormat">1|' "$PREFS_FILE"

# 2. Temperature units: set to "Metric" (Celsius) — agent must change to "Imperial" (Fahrenheit)
sed -i 's|name="preferenceKey_weather_temperatureUnits">[^<]*|name="preferenceKey_weather_temperatureUnits">Metric|' "$PREFS_FILE"

# 3. GPS coordinate format: set to "0" (Degrees) — agent must change to "1" (DMS)
sed -i 's|name="preferenceKey_regional_gpsFormat">[^<]*|name="preferenceKey_regional_gpsFormat">0|' "$PREFS_FILE"

# 4. Time format: set to "0" (System) — agent must change to "1" (12h)
sed -i 's|name="preferenceKey_regional_timeFormat">[^<]*|name="preferenceKey_regional_timeFormat">0|' "$PREFS_FILE"

# 5. Color scheme: set to "0" (Switch automatically) — agent must change to "2" (Night mode)
sed -i 's|name="preferenceKey_app_theme">[^<]*|name="preferenceKey_app_theme">0|' "$PREFS_FILE"

echo "All preferences reset to defaults."

# --- Record baseline snapshot for gate check ---
BASELINE_DISTANCE=$(grep 'preferenceKey_regional_distanceUnitsFormat' "$PREFS_FILE" | sed 's/.*>\([^<]*\)<.*/\1/')
BASELINE_TEMP=$(grep 'preferenceKey_weather_temperatureUnits' "$PREFS_FILE" | sed 's/.*>\([^<]*\)<.*/\1/')
BASELINE_GPS=$(grep 'preferenceKey_regional_gpsFormat' "$PREFS_FILE" | sed 's/.*>\([^<]*\)<.*/\1/')
BASELINE_TIME=$(grep 'preferenceKey_regional_timeFormat' "$PREFS_FILE" | sed 's/.*>\([^<]*\)<.*/\1/')
BASELINE_THEME=$(grep 'preferenceKey_app_theme' "$PREFS_FILE" | sed 's/.*>\([^<]*\)<.*/\1/')

echo "$BASELINE_DISTANCE" > /data/local/tmp/baseline_distance_units
echo "$BASELINE_TEMP" > /data/local/tmp/baseline_temperature_units
echo "$BASELINE_GPS" > /data/local/tmp/baseline_gps_format
echo "$BASELINE_TIME" > /data/local/tmp/baseline_time_format
echo "$BASELINE_THEME" > /data/local/tmp/baseline_color_scheme

echo "Baseline — distance=$BASELINE_DISTANCE temp=$BASELINE_TEMP gps=$BASELINE_GPS time=$BASELINE_TIME theme=$BASELINE_THEME"

# Record task start timestamp
date +%s > /data/local/tmp/task_start_timestamp

# --- Launch the app ---
input keyevent KEYCODE_HOME
sleep 1

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

# Take initial screenshot for reference
screencap -p /data/local/tmp/task_start_screenshot.png 2>/dev/null

echo "=== prepare_international_trip task setup complete ==="
echo "App should be on main map screen. Agent should navigate to Settings > View & Units and change all 5 settings."
