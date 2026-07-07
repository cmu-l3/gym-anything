#!/system/bin/sh
# Post-start setup script for Android AVD Calculator environment
# This runs via: adb shell sh /sdcard/scripts/setup_calculator.sh

echo "=== Setting up Android AVD Calculator Environment ==="

# Wait for system to be fully ready
sleep 3

# Press Home to ensure we're at home screen
input keyevent KEYCODE_HOME
sleep 1

# Check if OpenCalc is already installed
if pm list packages | grep -q "com.darkempire78.opencalculator"; then
    echo "OpenCalc already installed"
else
    echo "Installing OpenCalc APK..."
    # APK should be pushed to device via mounts. pm cannot read APKs from
    # /sdcard on modern Android, so stage it in /data/local/tmp first.
    if [ -f /sdcard/scripts/apks/opencalculator.apk ]; then
        cp /sdcard/scripts/apks/opencalculator.apk /data/local/tmp/opencalculator.apk
        pm install -r /data/local/tmp/opencalculator.apk
        if [ $? -eq 0 ]; then
            echo "OpenCalc installed successfully"
        else
            echo "ERROR: Failed to install OpenCalc"
            exit 1
        fi
        rm -f /data/local/tmp/opencalculator.apk
    else
        echo "ERROR: OpenCalc APK not found at /sdcard/scripts/apks/opencalculator.apk"
        exit 1
    fi
fi

# Launch Calculator app
echo "Launching Calculator..."
monkey -p com.darkempire78.opencalculator -c android.intent.category.LAUNCHER 1 2>/dev/null

if [ $? -eq 0 ]; then
    echo "Started OpenCalc"
else
    echo "Failed to start OpenCalc - trying other calculators..."
    # Try Google Calculator as fallback
    am start -n com.google.android.calculator/com.android.calculator2.Calculator 2>/dev/null && echo "Started Google Calculator" && exit 0
    # Generic calculator intent
    am start -a android.intent.action.MAIN -c android.intent.category.APP_CALCULATOR 2>/dev/null && echo "Started Calculator via intent" && exit 0
    echo "No calculator found"
fi

sleep 2
echo "=== Calculator setup completed ==="
