#!/system/bin/sh
# Export script for vfr_navaid_routing task.
# Reads SharedPreferences for chart type and collects all saved plan files.

echo "=== Exporting vfr_navaid_routing result ==="

PACKAGE="com.ds.avare"

# Take final screenshot for evidence
screencap -p /sdcard/avare_vfr_final.png 2>/dev/null

# Force stop app to flush SharedPreferences to disk
am force-stop $PACKAGE
sleep 3

# --- Read SharedPreferences ---
PREFS_COPIED="false"
for PREFS_PATH in "/data/data/com.ds.avare/shared_prefs/com.ds.avare_preferences.xml" \
                  "/data/user/0/com.ds.avare/shared_prefs/com.ds.avare_preferences.xml"; do
    if [ -f "$PREFS_PATH" ]; then
        cp "$PREFS_PATH" /sdcard/avare_prefs.xml
        PREFS_COPIED="true"
        echo "Copied preferences from $PREFS_PATH"
        break
    fi
done

if [ "$PREFS_COPIED" = "false" ]; then
    echo "<map></map>" > /sdcard/avare_prefs.xml
    echo "WARNING: SharedPreferences not found"
fi

# --- Collect plan files ---
PLAN_COUNT=0
rm -f /sdcard/avare_plans_combined.txt

if [ -d /sdcard/avare/Plans ]; then
    for f in /sdcard/avare/Plans/*.csv; do
        if [ -f "$f" ]; then
            PLAN_COUNT=$((PLAN_COUNT + 1))
            echo "=== $(basename $f) ===" >> /sdcard/avare_plans_combined.txt
            cat "$f" >> /sdcard/avare_plans_combined.txt
            echo "" >> /sdcard/avare_plans_combined.txt
        fi
    done
fi

echo "$PLAN_COUNT" > /sdcard/avare_plan_count.txt

if [ "$PLAN_COUNT" -gt "0" ]; then
    echo "Found $PLAN_COUNT saved plan file(s)"
else
    echo "No saved plan files found"
    # Create empty combined file so verifier copy_from_env doesn't hard-fail
    echo "NO_PLANS" > /sdcard/avare_plans_combined.txt
fi

echo "=== Export complete ==="
