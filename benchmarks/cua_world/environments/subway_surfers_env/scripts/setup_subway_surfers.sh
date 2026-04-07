#!/system/bin/sh
# Post-start setup script for Subway Surfers environment
# This runs via: adb shell sh /sdcard/scripts/setup_subway_surfers.sh

echo "=== Setting up Subway Surfers Environment ==="

# Wait for system to be fully ready
sleep 5

# Press Home to ensure we're at home screen
input keyevent KEYCODE_HOME
sleep 2

# Package name for Subway Surfers
PACKAGE="com.kiloo.subwaysurf"

# Check if Subway Surfers is already installed
echo "Checking if Subway Surfers is installed..."
if pm list packages | grep -q "$PACKAGE"; then
    echo "Subway Surfers already installed"
else
    echo "Subway Surfers not installed - attempting installation"

    APK_PATH="/sdcard/scripts/apks/subway_surfers.apk"

    # Check if APK exists and show details
    echo "Looking for APK at: $APK_PATH"
    if [ -f "$APK_PATH" ]; then
        echo "APK found!"
        ls -la "$APK_PATH"

        # Get file size
        APK_SIZE=$(ls -la "$APK_PATH" | awk '{print $5}')
        echo "APK size: $APK_SIZE bytes"

        echo "Installing Subway Surfers from APK (this may take a while for large APKs)..."

        # Try installation with different methods
        # Method 1: Standard pm install
        echo "Trying pm install..."
        pm install -r -d "$APK_PATH" 2>&1
        INSTALL_RESULT=$?

        if [ $INSTALL_RESULT -eq 0 ]; then
            echo "Installation successful via pm install"
        else
            echo "pm install failed with code $INSTALL_RESULT"

            # Method 2: Try with -g flag (grant all permissions)
            echo "Trying pm install with -g flag..."
            pm install -r -d -g "$APK_PATH" 2>&1
            INSTALL_RESULT=$?

            if [ $INSTALL_RESULT -eq 0 ]; then
                echo "Installation successful via pm install -g"
            else
                echo "pm install -g also failed"

                # Method 3: Copy to app-accessible location first
                echo "Trying to copy APK to /data/local/tmp first..."
                cp "$APK_PATH" /data/local/tmp/subway_surfers.apk 2>&1
                if [ -f /data/local/tmp/subway_surfers.apk ]; then
                    chmod 644 /data/local/tmp/subway_surfers.apk
                    pm install -r -d /data/local/tmp/subway_surfers.apk 2>&1
                    INSTALL_RESULT=$?
                    rm -f /data/local/tmp/subway_surfers.apk

                    if [ $INSTALL_RESULT -eq 0 ]; then
                        echo "Installation successful from /data/local/tmp"
                    fi
                fi
            fi
        fi

        # Final check
        if pm list packages | grep -q "$PACKAGE"; then
            echo "Subway Surfers installed successfully!"
        else
            echo "ERROR: Failed to install Subway Surfers after all attempts"
            echo "Listing installed packages for debugging:"
            pm list packages | head -20
        fi
    else
        echo "ERROR: APK not found at $APK_PATH"
        echo "Contents of /sdcard/scripts/:"
        ls -la /sdcard/scripts/ 2>&1 || echo "Cannot list /sdcard/scripts/"
        echo "Contents of /sdcard/scripts/apks/:"
        ls -la /sdcard/scripts/apks/ 2>&1 || echo "Cannot list /sdcard/scripts/apks/"
    fi
fi

# Verify installation status
echo ""
echo "=== Installation Status ==="
if pm list packages | grep -q "$PACKAGE"; then
    echo "Subway Surfers: INSTALLED"

    # Wait a moment for package to be ready
    sleep 2

    # Launch Subway Surfers
    echo "Launching Subway Surfers..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null

    if [ $? -eq 0 ]; then
        echo "Started Subway Surfers via monkey"
    else
        echo "Trying am start..."
        am start -n $PACKAGE/com.sybo.googleplay.SubwaySurfersUnityActivity 2>/dev/null
    fi

    # Wait for game to load
    echo "Waiting for game to load..."
    sleep 10

    # Handle potential initial screens/dialogs
    echo "Handling initial dialogs..."

    # Press back to dismiss any popups
    input keyevent KEYCODE_BACK
    sleep 1

    # Tap center to dismiss any "tap to continue" screens
    input tap 540 1200
    sleep 2

    # Handle GDPR/privacy consent if present (tap "Accept" area)
    input tap 800 2100
    sleep 1

    # Handle age verification/COPPA dialogs
    input tap 540 1800
    sleep 1

    # Tap center again to advance past any splash screens
    input tap 540 1200
    sleep 2

    echo "=== Subway Surfers setup completed ==="
else
    echo "Subway Surfers: NOT INSTALLED"
    echo "WARNING: Game is not available for testing"
fi
