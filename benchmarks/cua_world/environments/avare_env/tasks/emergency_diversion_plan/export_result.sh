#!/system/bin/sh
# Export script for emergency_diversion_plan task.
# Checks for the EMER.csv plan file specifically.

echo "=== Exporting emergency_diversion_plan result ==="

PACKAGE="com.ds.avare"

screencap -p /sdcard/avare_emer_final.png 2>/dev/null

am force-stop $PACKAGE
sleep 3

# Look for EMER.csv (case-insensitive search)
EMER_FOUND="false"
EMER_CONTENT=""

for f in /sdcard/avare/Plans/EMER.csv /sdcard/avare/Plans/emer.csv /sdcard/avare/Plans/Emer.csv; do
    if [ -f "$f" ]; then
        EMER_FOUND="true"
        cp "$f" /sdcard/avare_emer_plan.txt
        echo "Found EMER plan at $f"
        break
    fi
done

if [ "$EMER_FOUND" = "false" ]; then
    echo "EMER plan not found"
    echo "NO_EMER" > /sdcard/avare_emer_plan.txt
fi

# Also collect all plan files for inspection
PLAN_COUNT=0
rm -f /sdcard/avare_emer_all_plans.txt
if [ -d /sdcard/avare/Plans ]; then
    for f in /sdcard/avare/Plans/*.csv; do
        if [ -f "$f" ]; then
            PLAN_COUNT=$((PLAN_COUNT + 1))
            echo "=== $(basename $f) ===" >> /sdcard/avare_emer_all_plans.txt
            cat "$f" >> /sdcard/avare_emer_all_plans.txt
            echo "" >> /sdcard/avare_emer_all_plans.txt
        fi
    done
fi
if [ "$PLAN_COUNT" -eq "0" ]; then
    echo "NO_PLANS" > /sdcard/avare_emer_all_plans.txt
fi

echo "$EMER_FOUND" > /sdcard/avare_emer_found.txt

echo "=== Export complete ==="
