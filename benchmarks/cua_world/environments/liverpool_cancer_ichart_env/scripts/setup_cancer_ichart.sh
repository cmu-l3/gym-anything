#!/system/bin/sh
# Post-start setup script for Liverpool Cancer iChart Archive environment.
# This runs via: adb shell sh /sdcard/scripts/setup_cancer_ichart.sh
# Installs the APK and handles the first-run interaction data download.

echo "=== Setting up Liverpool Cancer iChart Environment ==="

# Wait for system to be fully ready
sleep 5

# Press Home to ensure we're at home screen
input keyevent KEYCODE_HOME
sleep 2

PACKAGE="com.liverpooluni.ichartoncology"
APK_PATH="/sdcard/scripts/apks/com.liverpooluni.ichartoncology.apk"

# Check if already installed
echo "Checking if Cancer iChart is installed..."
if pm list packages | grep -q "$PACKAGE"; then
    echo "Cancer iChart: ALREADY INSTALLED"
else
    echo "Installing Cancer iChart Archive..."

    if [ ! -f "$APK_PATH" ]; then
        echo "ERROR: APK not found at $APK_PATH"
        ls -la /sdcard/scripts/apks/ 2>&1
        exit 1
    fi

    # Copy to /data/local/tmp for SELinux compatibility
    cp "$APK_PATH" /data/local/tmp/cancer_ichart.apk
    chmod 644 /data/local/tmp/cancer_ichart.apk

    # Install
    pm install /data/local/tmp/cancer_ichart.apk 2>&1
    rm -f /data/local/tmp/cancer_ichart.apk

    # Verify
    if pm list packages | grep -q "$PACKAGE"; then
        echo "Cancer iChart installed successfully!"
    else
        echo "ERROR: Installation failed"
        exit 1
    fi
fi

# ==========================================
# First-run warmup: handle interaction data download dialog
# ==========================================
echo "Launching Cancer iChart for first-run warmup..."
input keyevent KEYCODE_WAKEUP 2>/dev/null || true
sleep 1
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null || true
sleep 10

# The first launch shows a "Get Interaction Data" dialog with OK/CANCEL buttons.
# Tap OK to install the drug interaction database.
# OK button is at approximately [763,1348][868,1458]
echo "Handling 'Get Interaction Data' dialog - tapping OK..."
input tap 815 1403
sleep 15

# Wait for data download to complete (interaction database is small)
echo "Waiting for interaction data download..."
sleep 15

# Force stop to get clean state for tasks
am force-stop $PACKAGE
sleep 1

echo "=== Liverpool Cancer iChart environment setup complete ==="
