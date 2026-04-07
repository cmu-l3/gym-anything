#!/system/bin/sh
# Export script for create_custom_checklist task
# Checks for persistence of the checklist and captures evidence

echo "=== Exporting results ==="

PACKAGE="com.ds.avare"
RESULT_FILE="/sdcard/task_result.json"

# 1. Capture final screenshot
screencap -p /sdcard/final_screenshot.png
echo "Screenshot captured."

# 2. Dump UI hierarchy (backup verification)
uiautomator dump /sdcard/ui_dump.xml 2>/dev/null

# 3. Check for persistence in app data
# Avare often stores lists in shared_prefs or JSON files in files/
# We search for the target string "C172 Runup" in the package data directory.
# Requires root/su usually, assuming environment allows it or files are world-readable.

STRINGS_FOUND="false"
TITLE_FOUND="false"
ITEMS_FOUND_COUNT=0

# Try to grep in data directory (might fail if no root, but worth a try in emulator env)
# If su is available:
if which su >/dev/null; then
    echo "Searching internal storage with su..."
    
    # Check Title
    if su 0 grep -r "C172 Runup" /data/data/$PACKAGE/ 2>/dev/null; then
        TITLE_FOUND="true"
    fi
    
    # Check Items
    if su 0 grep -r "Doors Closed" /data/data/$PACKAGE/ 2>/dev/null; then
        ITEMS_FOUND_COUNT=$((ITEMS_FOUND_COUNT + 1))
    fi
    if su 0 grep -r "Mags Both" /data/data/$PACKAGE/ 2>/dev/null; then
        ITEMS_FOUND_COUNT=$((ITEMS_FOUND_COUNT + 1))
    fi
    if su 0 grep -r "Carb Heat Cold" /data/data/$PACKAGE/ 2>/dev/null; then
        ITEMS_FOUND_COUNT=$((ITEMS_FOUND_COUNT + 1))
    fi
else
    echo "No root access, skipping internal storage search."
    # Fallback: check /sdcard/Android/data if app stores data there
    if grep -r "C172 Runup" /sdcard/Android/data/$PACKAGE/ 2>/dev/null; then
        TITLE_FOUND="true"
    fi
fi

if [ "$TITLE_FOUND" = "true" ]; then
    STRINGS_FOUND="true"
fi

# 4. Check if app is running
APP_RUNNING="false"
if pidof $PACKAGE >/dev/null; then
    APP_RUNNING="true"
fi

# 5. Create JSON result
echo "{" > $RESULT_FILE
echo "  \"app_running\": $APP_RUNNING," >> $RESULT_FILE
echo "  \"persistence_check\": {" >> $RESULT_FILE
echo "    \"title_found\": $TITLE_FOUND," >> $RESULT_FILE
echo "    \"items_found_count\": $ITEMS_FOUND_COUNT" >> $RESULT_FILE
echo "  }," >> $RESULT_FILE
echo "  \"screenshot_path\": \"/sdcard/final_screenshot.png\"" >> $RESULT_FILE
echo "}" >> $RESULT_FILE

echo "Result exported to $RESULT_FILE"
cat $RESULT_FILE
echo "=== Export complete ==="