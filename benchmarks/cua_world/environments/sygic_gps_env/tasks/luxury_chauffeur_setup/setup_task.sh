#!/system/bin/sh
# Setup script for luxury_chauffeur_setup task.
# Resets 5 settings to their wrong/default state — agent must correct all of them.
# No vehicle profile creation required: the task is pure settings configuration.

if [ "$(id -u)" != "0" ]; then
    exec su 0 sh "$0" "$@"
fi

echo "=== Setting up luxury_chauffeur_setup task ==="

PACKAGE="com.sygic.aura"
PREFS_FILE="/data/data/$PACKAGE/shared_prefs/com.sygic.aura_preferences.xml"

# Force stop for clean state and pref flush
am force-stop $PACKAGE
sleep 2

# Set starting state that the agent must fix (all wrong for luxury chauffeur service):

# Arrive-in-direction = false -- must enable (true)
sed -i 's/name="preferenceKey_arriveInDrivingSide" value="[^"]*"/name="preferenceKey_arriveInDrivingSide" value="false"/' "$PREFS_FILE"

# App theme = Auto (0) -- must change to Night (2)
sed -i 's|name="preferenceKey_app_theme">[^<]*|name="preferenceKey_app_theme">0|' "$PREFS_FILE"

# Toll roads avoided = true -- must set to NOT avoided (false)
sed -i 's/name="tmp_preferenceKey_routePlanning_tollRoads_avoid" value="[^"]*"/name="tmp_preferenceKey_routePlanning_tollRoads_avoid" value="true"/' "$PREFS_FILE"

# Compass always on = false -- must enable (true)
sed -i 's/name="preferenceKey_navigation_compassAlwaysOn" value="[^"]*"/name="preferenceKey_navigation_compassAlwaysOn" value="false"/' "$PREFS_FILE"

# GPS coordinate format = Degrees (0) -- must change to DMS (1)
sed -i 's|name="preferenceKey_regional_gpsFormat">[^<]*|name="preferenceKey_regional_gpsFormat">0|' "$PREFS_FILE"

# Record baseline values for gate check
BASELINE_ARRIVE=$(grep 'preferenceKey_arriveInDrivingSide' "$PREFS_FILE" | sed 's/.*value="\([^"]*\)".*/\1/')
BASELINE_THEME=$(grep 'preferenceKey_app_theme' "$PREFS_FILE" | sed 's/.*>\([^<]*\)<.*/\1/')
BASELINE_TOLLS=$(grep 'tmp_preferenceKey_routePlanning_tollRoads_avoid' "$PREFS_FILE" | sed 's/.*value="\([^"]*\)".*/\1/')
BASELINE_COMPASS=$(grep 'preferenceKey_navigation_compassAlwaysOn' "$PREFS_FILE" | sed 's/.*value="\([^"]*\)".*/\1/')
BASELINE_GPS=$(grep 'preferenceKey_regional_gpsFormat' "$PREFS_FILE" | sed 's/.*>\([^<]*\)<.*/\1/')

echo "$BASELINE_ARRIVE" > /data/local/tmp/luxury_chauffeur_setup_baseline_arrive
echo "$BASELINE_THEME" > /data/local/tmp/luxury_chauffeur_setup_baseline_theme
echo "$BASELINE_TOLLS" > /data/local/tmp/luxury_chauffeur_setup_baseline_tolls
echo "$BASELINE_COMPASS" > /data/local/tmp/luxury_chauffeur_setup_baseline_compass
echo "$BASELINE_GPS" > /data/local/tmp/luxury_chauffeur_setup_baseline_gps

echo "Baselines: arrive=$BASELINE_ARRIVE theme=$BASELINE_THEME tolls=$BASELINE_TOLLS compass=$BASELINE_COMPASS gps=$BASELINE_GPS"

# Record task start timestamp
date +%s > /data/local/tmp/luxury_chauffeur_setup_start_ts

# Press Home, then launch app
input keyevent KEYCODE_HOME
sleep 1

echo "Launching Sygic GPS Navigation..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 12

CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher"; then
    echo "App not in foreground, relaunching..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 10
fi

screencap -p /data/local/tmp/luxury_chauffeur_setup_start_screenshot.png 2>/dev/null

echo "=== luxury_chauffeur_setup setup complete ==="
