#!/system/bin/sh
# Export script for ifr_valley_routing task.
# Collects: saved plan from user.db, SharedPreferences (chart type),
# app state, and screenshots for verification.
#
# Key finding from live testing: Avare stores plans in SQLite (user.db
# table 'plans'), NOT as CSV files. Each plan row has:
#   name TEXT, path TEXT (JSON array of waypoint strings)
# Waypoint format: "ID::Type;SubType;Name"
# Example: "SJC::Navaid;VOR/DME;SAN JOSE 114.10"
#          "SAC::Base;Airport;SACRAMENTO EXEC"

echo "=== Exporting ifr_valley_routing result ==="

PACKAGE="com.ds.avare"
RESULT_JSON="/sdcard/task_result.json"

# 1. Take final screenshot before stopping app
screencap -p /sdcard/task_final.png 2>/dev/null

# 2. Check if app is running
APP_RUNNING="false"
if pidof $PACKAGE > /dev/null 2>&1; then
    APP_RUNNING="true"
fi

# 3. Force-stop to flush SharedPreferences and database to disk
am force-stop $PACKAGE
sleep 3

# 4. Read SharedPreferences
PREFS_COPIED="false"
CHART_TYPE=""
PREFS_LOCAL="/sdcard/avare_ifr_valley_prefs.xml"

su root cp /data/data/com.ds.avare/shared_prefs/com.ds.avare_preferences.xml "$PREFS_LOCAL" 2>/dev/null
if [ ! -f "$PREFS_LOCAL" ]; then
    su root cp /data/user/0/com.ds.avare/shared_prefs/com.ds.avare_preferences.xml "$PREFS_LOCAL" 2>/dev/null
fi

if [ -f "$PREFS_LOCAL" ]; then
    chmod 644 "$PREFS_LOCAL" 2>/dev/null
    PREFS_COPIED="true"
    # Extract chart type — if key is absent, default is Sectional
    CHART_TYPE=$(grep -o 'ChartType">[^<]*' "$PREFS_LOCAL" 2>/dev/null | sed 's/ChartType">//')
    if [ -z "$CHART_TYPE" ]; then
        CHART_TYPE="Sectional"
    fi
else
    CHART_TYPE="unknown"
fi

# 5. Read plan data from user.db SQLite
PLAN_EXISTS="false"
PLAN_DATA=""
PLAN_NAME_FOUND=""
PLAN_HAS_NAVAID_SJC="false"
PLAN_HAS_AIRPORT_SJC="false"
PLAN_HAS_NAVAID_MOD="false"
PLAN_HAS_AIRPORT_MOD="false"
PLAN_HAS_NAVAID_SAC="false"
PLAN_HAS_AIRPORT_SAC="false"
PLAN_WAYPOINT_COUNT=0

# Query plans from user.db (try both data paths)
USER_DB=""
for DB_PATH in "/data/data/com.ds.avare/files/user.db" \
               "/data/user/0/com.ds.avare/files/user.db"; do
    if su root test -f "$DB_PATH" 2>/dev/null; then
        USER_DB="$DB_PATH"
        break
    fi
done

if [ -n "$USER_DB" ]; then
    # Check for IFR_VALLEY plan (case-insensitive)
    PLAN_DATA=$(su root sqlite3 "$USER_DB" "SELECT path FROM plans WHERE name LIKE '%IFR%VALLEY%' LIMIT 1;" 2>/dev/null)

    if [ -n "$PLAN_DATA" ]; then
        PLAN_EXISTS="true"
        PLAN_NAME_FOUND=$(su root sqlite3 "$USER_DB" "SELECT name FROM plans WHERE name LIKE '%IFR%VALLEY%' LIMIT 1;" 2>/dev/null)

        # Count waypoints (count occurrences of "::" separator in the JSON array)
        PLAN_WAYPOINT_COUNT=$(echo "$PLAN_DATA" | grep -o '::' | wc -l)

        # Check for VOR (Navaid) vs Airport entries
        # VOR entries contain "::Navaid" in the plan path
        # Airport entries contain "::Base" in the plan path
        if echo "$PLAN_DATA" | grep -q 'SJC::Navaid'; then
            PLAN_HAS_NAVAID_SJC="true"
        fi
        if echo "$PLAN_DATA" | grep -q 'SJC::Base'; then
            PLAN_HAS_AIRPORT_SJC="true"
        fi
        if echo "$PLAN_DATA" | grep -q 'MOD::Navaid'; then
            PLAN_HAS_NAVAID_MOD="true"
        fi
        if echo "$PLAN_DATA" | grep -q 'MOD::Base'; then
            PLAN_HAS_AIRPORT_MOD="true"
        fi
        if echo "$PLAN_DATA" | grep -q 'SAC::Navaid'; then
            PLAN_HAS_NAVAID_SAC="true"
        fi
        if echo "$PLAN_DATA" | grep -q 'SAC::Base'; then
            PLAN_HAS_AIRPORT_SAC="true"
        fi
    fi

    # Save all plan data for inspection
    su root sqlite3 "$USER_DB" "SELECT name, path FROM plans;" > /sdcard/avare_ifr_valley_plans.txt 2>/dev/null
fi

# 6. Get task timestamps
TASK_START=$(cat /sdcard/avare_task_start_timestamp.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 7. Build result JSON
echo "{" > $RESULT_JSON
echo "  \"task_start\": $TASK_START," >> $RESULT_JSON
echo "  \"task_end\": $TASK_END," >> $RESULT_JSON
echo "  \"app_running\": $APP_RUNNING," >> $RESULT_JSON
echo "  \"prefs_copied\": $PREFS_COPIED," >> $RESULT_JSON
echo "  \"chart_type\": \"$CHART_TYPE\"," >> $RESULT_JSON
echo "  \"plan_exists\": $PLAN_EXISTS," >> $RESULT_JSON
echo "  \"plan_name\": \"$PLAN_NAME_FOUND\"," >> $RESULT_JSON
echo "  \"plan_waypoint_count\": $PLAN_WAYPOINT_COUNT," >> $RESULT_JSON
echo "  \"plan_has_navaid_sjc\": $PLAN_HAS_NAVAID_SJC," >> $RESULT_JSON
echo "  \"plan_has_airport_sjc\": $PLAN_HAS_AIRPORT_SJC," >> $RESULT_JSON
echo "  \"plan_has_navaid_mod\": $PLAN_HAS_NAVAID_MOD," >> $RESULT_JSON
echo "  \"plan_has_airport_mod\": $PLAN_HAS_AIRPORT_MOD," >> $RESULT_JSON
echo "  \"plan_has_navaid_sac\": $PLAN_HAS_NAVAID_SAC," >> $RESULT_JSON
echo "  \"plan_has_airport_sac\": $PLAN_HAS_AIRPORT_SAC," >> $RESULT_JSON
echo "  \"screenshot_path\": \"/sdcard/task_final.png\"" >> $RESULT_JSON
echo "}" >> $RESULT_JSON

echo "=== Export complete ==="
cat $RESULT_JSON
