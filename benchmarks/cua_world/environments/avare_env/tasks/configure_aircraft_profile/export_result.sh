#!/system/bin/sh
echo "=== Exporting task results ==="

PACKAGE="com.ds.avare"
PREFS_DIR="/data/data/$PACKAGE/shared_prefs"
TMP_DIR="/data/local/tmp"
RESULT_JSON="$TMP_DIR/task_result.json"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat "$TMP_DIR/task_start_time.txt" 2>/dev/null || echo "0")

# 1. Check if SharedPreferences were modified
PREFS_MODIFIED="false"
# We check if any XML file in the prefs dir has a modification time > TASK_START
if [ -d "$PREFS_DIR" ]; then
    for f in "$PREFS_DIR"/*.xml; do
        if [ -f "$f" ]; then
            MTIME=$(stat -c %Y "$f" 2>/dev/null || echo "0")
            if [ "$MTIME" -gt "$TASK_START" ]; then
                PREFS_MODIFIED="true"
                break
            fi
        fi
    done
fi

# 2. Check for specific values in the preferences (Fuel=10, TAS=115)
# Avare stores these as strings or floats in XML.
# We look for the values "10", "10.0", "115", "115.0" specifically associated 
# with keys that look like performance settings (or just presence in the file if specific keys are unknown).
# Note: exact keys might be 'FuelBurn', 'AircraftTAS', etc. We search broadly to be robust.

FOUND_FUEL="false"
FOUND_TAS="false"

if [ -d "$PREFS_DIR" ]; then
    # Grep recursively in prefs dir
    # Look for value="10" or value="10.0"
    if grep -E 'value="10"|value="10.0"' "$PREFS_DIR"/*.xml >/dev/null 2>&1; then
        FOUND_FUEL="true"
    fi
    
    # Look for value="115" or value="115.0"
    if grep -E 'value="115"|value="115.0"' "$PREFS_DIR"/*.xml >/dev/null 2>&1; then
        FOUND_TAS="true"
    fi
fi

# 3. Check if App is currently running and on Map (Main) Activity
# We check if the resumed activity belongs to Avare and is NOT the Preferences activity
APP_RUNNING="false"
ON_MAP_SCREEN="false"

# Get current focus
CURRENT_FOCUS=$(dumpsys window windows | grep -E 'mCurrentFocus|mFocusedApp' 2>/dev/null)

if echo "$CURRENT_FOCUS" | grep -q "$PACKAGE"; then
    APP_RUNNING="true"
    # Check if we are in Preferences (bad) or Main/Map (good)
    # Preferences activity usually has "Preference" or "Settings" in name
    if echo "$CURRENT_FOCUS" | grep -q "Preference"; then
        ON_MAP_SCREEN="false"
    elif echo "$CURRENT_FOCUS" | grep -q "Settings"; then
        ON_MAP_SCREEN="false"
    else
        # Likely the main map activity (MainActivity or similar)
        ON_MAP_SCREEN="true"
    fi
fi

# Capture final screenshot
screencap -p "$TMP_DIR/task_final.png"

# Construct JSON result
# Note: Android shell mksh doesn't handle complex JSON creation well, so we cat simple strings
echo "{" > "$RESULT_JSON"
echo "  \"task_start\": $TASK_START," >> "$RESULT_JSON"
echo "  \"task_end\": $TASK_END," >> "$RESULT_JSON"
echo "  \"prefs_modified\": $PREFS_MODIFIED," >> "$RESULT_JSON"
echo "  \"found_fuel_value\": $FOUND_FUEL," >> "$RESULT_JSON"
echo "  \"found_tas_value\": $FOUND_TAS," >> "$RESULT_JSON"
echo "  \"app_running\": $APP_RUNNING," >> "$RESULT_JSON"
echo "  \"on_map_screen\": $ON_MAP_SCREEN," >> "$RESULT_JSON"
echo "  \"screenshot_path\": \"$TMP_DIR/task_final.png\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

# Output for debugging log
cat "$RESULT_JSON"

echo "=== Export complete ==="