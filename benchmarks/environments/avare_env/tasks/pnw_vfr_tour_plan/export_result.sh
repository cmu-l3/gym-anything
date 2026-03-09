#!/system/bin/sh
# Export script for pnw_vfr_tour_plan task.
# Checks specifically for PNW_TOUR.csv and reads SharedPreferences for chart type.

echo "=== Exporting pnw_vfr_tour_plan result ==="

PACKAGE="com.ds.avare"

screencap -p /sdcard/avare_pnw_final.png 2>/dev/null

am force-stop $PACKAGE
sleep 3

# --- Read SharedPreferences ---
PREFS_COPIED="false"
for PREFS_PATH in "/data/data/com.ds.avare/shared_prefs/com.ds.avare_preferences.xml" \
                  "/data/user/0/com.ds.avare/shared_prefs/com.ds.avare_preferences.xml"; do
    if [ -f "$PREFS_PATH" ]; then
        cp "$PREFS_PATH" /sdcard/avare_pnw_prefs.xml
        PREFS_COPIED="true"
        echo "Copied preferences from $PREFS_PATH"
        break
    fi
done

if [ "$PREFS_COPIED" = "false" ]; then
    echo "<map></map>" > /sdcard/avare_pnw_prefs.xml
    echo "WARNING: SharedPreferences not found"
fi

# --- Look for PNW_TOUR plan specifically ---
PNW_FOUND="false"
for f in /sdcard/avare/Plans/PNW_TOUR.csv /sdcard/avare/Plans/pnw_tour.csv /sdcard/avare/Plans/PNW_tour.csv; do
    if [ -f "$f" ]; then
        PNW_FOUND="true"
        cp "$f" /sdcard/avare_pnw_tour_plan.txt
        echo "Found PNW_TOUR plan at $f"
        break
    fi
done

if [ "$PNW_FOUND" = "false" ]; then
    echo "PNW_TOUR plan not found"
    echo "NO_PNW_TOUR" > /sdcard/avare_pnw_tour_plan.txt
fi

echo "$PNW_FOUND" > /sdcard/avare_pnw_found.txt

# --- Also dump all plan files ---
PLAN_COUNT=0
rm -f /sdcard/avare_pnw_all_plans.txt
if [ -d /sdcard/avare/Plans ]; then
    for f in /sdcard/avare/Plans/*.csv; do
        if [ -f "$f" ]; then
            PLAN_COUNT=$((PLAN_COUNT + 1))
            echo "=== $(basename $f) ===" >> /sdcard/avare_pnw_all_plans.txt
            cat "$f" >> /sdcard/avare_pnw_all_plans.txt
            echo "" >> /sdcard/avare_pnw_all_plans.txt
        fi
    done
fi
if [ "$PLAN_COUNT" -eq "0" ]; then
    echo "NO_PLANS" > /sdcard/avare_pnw_all_plans.txt
fi

echo "=== Export complete ==="
