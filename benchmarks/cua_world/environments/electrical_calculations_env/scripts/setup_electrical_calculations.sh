#!/system/bin/sh
# Post-start setup script for Electrical Engineering Calculations environment.
# This runs via: adb shell sh /sdcard/scripts/setup_electrical_calculations.sh
# Installs the APK and launches the app for first-run warmup.

echo "=== Setting up Electrical Calculations Environment ==="

# Wait for system to be fully ready
sleep 5

# Press Home to ensure we're at home screen
input keyevent KEYCODE_HOME
sleep 2

PACKAGE="com.hsn.electricalcalculations"
APK_PATH="/sdcard/scripts/apks/com.hsn.electricalcalculations.apk"

# Check if already installed
echo "Checking if Electrical Calculations is installed..."
if pm list packages | grep -q "$PACKAGE"; then
    echo "Electrical Calculations: ALREADY INSTALLED"
else
    echo "Installing Electrical Calculations..."

    if [ ! -f "$APK_PATH" ]; then
        echo "ERROR: APK not found at $APK_PATH"
        ls -la /sdcard/scripts/apks/ 2>&1
        exit 1
    fi

    # Copy to /data/local/tmp for SELinux compatibility
    cp "$APK_PATH" /data/local/tmp/ec.apk
    chmod 644 /data/local/tmp/ec.apk

    # Install
    pm install /data/local/tmp/ec.apk 2>&1
    rm -f /data/local/tmp/ec.apk

    # Verify
    if pm list packages | grep -q "$PACKAGE"; then
        echo "Electrical Calculations installed successfully!"
    else
        echo "ERROR: Installation failed"
        exit 1
    fi
fi

# Launch app for first-run warmup (dismiss any initial dialogs)
echo "Launching Electrical Calculations for warmup..."
_RESOLVED=$(cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER "$PACKAGE" 2>/dev/null | tail -1)
if [ -n "$_RESOLVED" ] && echo "$_RESOLVED" | grep -q "/"; then
    am start -W -n "$_RESOLVED" 2>/dev/null || true
else
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null || true
fi
sleep 8

# Press back to dismiss any ad/promo overlay, then go home
input keyevent KEYCODE_BACK
sleep 2
input keyevent KEYCODE_HOME
sleep 1

# Force stop to get clean state for tasks
am force-stop $PACKAGE
sleep 1

echo "=== Electrical Calculations environment setup complete ==="
