#!/system/bin/sh
# Post-start setup script for Avare aviation GPS environment.
# Installs the APK, grants permissions, handles first-run registration and database download.
#
# First-run flow (observed on Android 14 emulator 1080x2400):
#   1. Nearby devices permission dialog -> Don't allow (or grant via pm)
#   2. RegisterActivity (Terms + email) -> enter email, tap Register -> OK dialog
#   3. Download screen -> tap Databases(1), expand, check "Databases (Required)", tap Get
#   4. Back -> main map view with "Download Sectional: SanFrancisco"
#
# After registration, subsequent launches go directly to the main map view.

echo "=== Setting up Avare Aviation GPS Environment ==="

# Wait for system to be fully ready
sleep 5

# Press Home to ensure we're at home screen
input keyevent KEYCODE_HOME
sleep 2

PACKAGE="com.ds.avare"
APK_PATH="/sdcard/scripts/apks/com.ds.avare.apk"

# Check if already installed
echo "Checking if Avare is installed..."
if pm list packages | grep -q "$PACKAGE"; then
    echo "Avare: ALREADY INSTALLED"
else
    echo "Installing Avare..."

    if [ ! -f "$APK_PATH" ]; then
        echo "ERROR: APK not found at $APK_PATH"
        ls -la /sdcard/scripts/apks/ 2>&1
        exit 1
    fi

    # Copy to /data/local/tmp for SELinux compatibility
    cp "$APK_PATH" /data/local/tmp/avare.apk
    chmod 644 /data/local/tmp/avare.apk

    # Install
    pm install /data/local/tmp/avare.apk 2>&1
    rm -f /data/local/tmp/avare.apk

    # Verify
    if pm list packages | grep -q "$PACKAGE"; then
        echo "Avare installed successfully!"
    else
        echo "ERROR: Avare installation failed"
        exit 1
    fi
fi

# Grant ALL permissions before first launch (avoids permission dialogs)
echo "Granting permissions..."
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.POST_NOTIFICATIONS 2>/dev/null
pm grant $PACKAGE android.permission.BLUETOOTH_SCAN 2>/dev/null
pm grant $PACKAGE android.permission.BLUETOOTH_CONNECT 2>/dev/null
pm grant $PACKAGE android.permission.NEARBY_WIFI_DEVICES 2>/dev/null

# ==========================================
# First-run warmup: handle registration + database download
# ==========================================
echo "Launching Avare for first-run warmup..."
_RESOLVED=$(cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER "$PACKAGE" 2>/dev/null | tail -1)
if [ -n "$_RESOLVED" ] && echo "$_RESOLVED" | grep -q "/"; then
    am start -W -n "$_RESOLVED" 2>/dev/null || true
else
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null || true
fi
sleep 12

# Step 1: Nearby devices permission dialog may still appear
# "Allow Avare to find, connect to, and determine the relative position of nearby devices?"
# Try tapping "Don't allow" button twice to cover both dialog states
# "Don't allow" button is at approximately (540, 1487) in 1080x2400 resolution
echo "Handling nearby devices permission dialog..."
input tap 540 1490
sleep 2
# Tap again in case a second permission dialog appears
input tap 540 1490
sleep 3

# Step 2: RegisterActivity - Terms, Conditions, and Privacy
# Email field at bounds [16,2015][797,2321], Register button at [803,2015][1064,2321]
echo "Handling registration screen..."
# Tap email field center (406, 2168)
input tap 406 2168
sleep 2
# Type email address
input text "pilot@test.com"
sleep 1
# Dismiss keyboard first
input keyevent KEYCODE_BACK
sleep 2
# Tap Register button center (933, 2168)
input tap 933 2168
echo "Tapped Register..."
sleep 8

# Step 3: "You have now registered!" dialog appears with OK button
# Tap OK button - the dialog is centered on screen
# OK button center approx (540, 1630)
echo "Handling registration success dialog..."
input tap 540 1630
sleep 3

# Step 4: Press Back to leave RegisterActivity and reach main app
input keyevent KEYCODE_BACK
sleep 5

# Step 5: "Required data file is missing" dialog may appear on map screen
# Dialog has "Download" button on left and "Cancel" on right
# Download button center: approx (323, 1387) but let's also try center tapping
echo "Handling database download dialog..."
input tap 350 1400
sleep 5

# Step 6: Now on the download manager screen with categories
# "Databases(1)" category at top - tap to expand it
echo "Expanding Databases category..."
input tap 287 350
sleep 2

# Step 7: "Databases (Required)" item should be checked (green checkbox)
# Tap "Get" button at top-left corner of screen to download
echo "Tapping Get to download database..."
input tap 152 203
sleep 3

# Wait for database download to complete (~2MB)
echo "Waiting for database download..."
sleep 25

# Go back to main map view
input keyevent KEYCODE_BACK
sleep 3

# Force stop to get clean state for tasks
am force-stop $PACKAGE
sleep 2

echo "=== Avare Aviation GPS environment setup complete ==="
