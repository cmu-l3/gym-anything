#!/system/bin/sh
# Post-start setup script for farmOS Field Kit environment.
# This runs via: adb shell sh /sdcard/scripts/setup_farmos.sh
# Installs the APK. No first-run flow needed - app works offline immediately.

echo "=== Setting up farmOS Field Kit Environment ==="

# Wait for system to be fully ready
sleep 5

# Press Home to ensure we're at home screen
input keyevent KEYCODE_HOME
sleep 2

PACKAGE="org.farmos.app"
APK_PATH="/sdcard/scripts/apks/org.farmos.app.apk"

# Check if already installed
echo "Checking if farmOS Field Kit is installed..."
if pm list packages | grep -q "$PACKAGE"; then
    echo "farmOS Field Kit: ALREADY INSTALLED"
else
    echo "Installing farmOS Field Kit..."

    if [ ! -f "$APK_PATH" ]; then
        echo "ERROR: APK not found at $APK_PATH"
        ls -la /sdcard/scripts/apks/ 2>&1
        exit 1
    fi

    # Copy to /data/local/tmp for SELinux compatibility
    cp "$APK_PATH" /data/local/tmp/farmos.apk
    chmod 644 /data/local/tmp/farmos.apk

    # Install
    pm install /data/local/tmp/farmos.apk 2>&1
    rm -f /data/local/tmp/farmos.apk

    # Verify
    if pm list packages | grep -q "$PACKAGE"; then
        echo "farmOS Field Kit installed successfully!"
    else
        echo "ERROR: Installation failed"
        exit 1
    fi
fi

# Grant location permissions
echo "Granting permissions..."
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION 2>/dev/null

# Launch once to initialize the app's internal state
echo "Launching farmOS Field Kit for initialization..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# Force stop to get clean state for tasks
am force-stop $PACKAGE
sleep 1

echo "=== farmOS Field Kit environment setup complete ==="
