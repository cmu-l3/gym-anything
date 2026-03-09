#!/system/bin/sh
# Post-start setup script for Flight Crew View (FLICA) environment
# This runs via: adb shell sh /sdcard/scripts/setup_flica.sh
# Handles split APK installation (App Bundle) and full login flow

echo "=== Setting up Flight Crew View Environment ==="

# Wait for system to be fully ready
sleep 5

# Press Home to ensure we're at home screen
input keyevent KEYCODE_HOME
sleep 2

# Package name for Flight Crew View
PACKAGE="com.robert.fcView"

# Check if Flight Crew View is already installed
echo "Checking if Flight Crew View is installed..."
if pm list packages | grep -q "$PACKAGE"; then
    echo "Flight Crew View: ALREADY INSTALLED"
else
    echo "Flight Crew View not installed - installing split APKs..."

    APK_DIR="/sdcard/scripts/apks"
    INSTALL_DIR="/data/local/tmp/fcview_install"
    BASE_APK="$APK_DIR/com.robert.fcView.apk"

    if [ ! -f "$BASE_APK" ]; then
        echo "ERROR: Base APK not found at $BASE_APK"
        ls -la "$APK_DIR/" 2>&1
        exit 1
    fi

    # Copy APKs to /data/local/tmp/ (required by SELinux for pm install)
    echo "Copying APKs to install directory..."
    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    cp "$APK_DIR"/com.robert.fcView.apk "$INSTALL_DIR/"
    cp "$APK_DIR"/config.*.apk "$INSTALL_DIR/"
    chmod 644 "$INSTALL_DIR"/*.apk

    # Install split APKs using pm install session
    echo "Creating install session..."
    SESSION_ID=$(pm install-create -r 2>&1 | grep -o '[0-9]*')
    echo "Session ID: $SESSION_ID"

    if [ -z "$SESSION_ID" ]; then
        echo "ERROR: Failed to create install session"
        rm -rf "$INSTALL_DIR"
        exit 1
    fi

    # Write base APK
    BASE_SIZE=$(wc -c < "$INSTALL_DIR/com.robert.fcView.apk")
    echo "Writing base APK ($BASE_SIZE bytes)..."
    pm install-write -S "$BASE_SIZE" "$SESSION_ID" base "$INSTALL_DIR/com.robert.fcView.apk"

    # Write config splits
    for SPLIT_APK in "$INSTALL_DIR"/config.*.apk; do
        if [ -f "$SPLIT_APK" ]; then
            SPLIT_NAME=$(basename "$SPLIT_APK" .apk)
            SPLIT_SIZE=$(wc -c < "$SPLIT_APK")
            echo "Writing split $SPLIT_NAME ($SPLIT_SIZE bytes)..."
            pm install-write -S "$SPLIT_SIZE" "$SESSION_ID" "$SPLIT_NAME" "$SPLIT_APK"
        fi
    done

    # Commit the install session
    echo "Committing install session..."
    INSTALL_RESULT=$(pm install-commit "$SESSION_ID" 2>&1)
    echo "Install result: $INSTALL_RESULT"

    # Cleanup
    rm -rf "$INSTALL_DIR"

    # Verify installation
    if pm list packages | grep -q "$PACKAGE"; then
        echo "Flight Crew View installed successfully!"
    else
        echo "ERROR: Installation failed"
        exit 1
    fi
fi

# Grant runtime permissions upfront to avoid permission dialogs
echo "Granting runtime permissions..."
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.POST_NOTIFICATIONS 2>/dev/null
pm grant $PACKAGE android.permission.READ_CALENDAR 2>/dev/null
pm grant $PACKAGE android.permission.WRITE_CALENDAR 2>/dev/null
pm grant $PACKAGE android.permission.READ_CONTACTS 2>/dev/null

# Launch Flight Crew View
echo "Launching Flight Crew View..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null

if [ $? -eq 0 ]; then
    echo "Started Flight Crew View via monkey"
else
    echo "Trying am start..."
    am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER $PACKAGE 2>/dev/null
fi

# Wait for app to load
echo "Waiting for app to load (15 seconds)..."
sleep 15

echo "=== Flight Crew View setup completed ==="
echo "App should be at the welcome/login screen or logged-in state"
