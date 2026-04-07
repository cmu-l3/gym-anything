#!/system/bin/sh
# Post-start setup script for Sygic GPS Navigation environment.
# This runs via: adb shell sh /sdcard/scripts/setup_sygic_gps.sh
# Installs the APK and handles the first-run flow (EULA, privacy, sign-up).

echo "=== Setting up Sygic GPS Navigation Environment ==="

# Wait for system to be fully ready
sleep 5

# Press Home to ensure we're at home screen
input keyevent KEYCODE_HOME
sleep 2

PACKAGE="com.sygic.aura"
APK_PATH="/sdcard/scripts/apks/com.sygic.aura.apk"

# Check if already installed
echo "Checking if Sygic GPS is installed..."
if pm list packages | grep -q "$PACKAGE"; then
    echo "Sygic GPS: ALREADY INSTALLED"
else
    echo "Installing Sygic GPS Navigation..."

    if [ ! -f "$APK_PATH" ]; then
        echo "ERROR: APK not found at $APK_PATH"
        ls -la /sdcard/scripts/apks/ 2>&1
        exit 1
    fi

    # Copy to /data/local/tmp for SELinux compatibility
    cp "$APK_PATH" /data/local/tmp/sygic.apk
    chmod 644 /data/local/tmp/sygic.apk

    # Install
    pm install /data/local/tmp/sygic.apk 2>&1
    rm -f /data/local/tmp/sygic.apk

    # Verify
    if pm list packages | grep -q "$PACKAGE"; then
        echo "Sygic GPS installed successfully!"
    else
        echo "ERROR: Installation failed"
        exit 1
    fi
fi

# Grant location permissions for GPS functionality
echo "Granting permissions..."
pm grant $PACKAGE android.permission.ACCESS_FINE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.ACCESS_COARSE_LOCATION 2>/dev/null
pm grant $PACKAGE android.permission.POST_NOTIFICATIONS 2>/dev/null

# ==========================================
# First-run warmup: handle EULA, privacy, premium, sign-up screens
# ==========================================
echo "Launching Sygic GPS for first-run warmup..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 15

# Step 1: EULA screen - tap "OK" button
# The OK button is a large blue button near the bottom of the EULA screen
echo "Handling EULA screen..."
input tap 540 2200
sleep 5

# Step 2: Privacy consent screen - tap "I agree" button
echo "Handling Privacy screen..."
input tap 540 2200
sleep 5

# Step 3: Premium upsell screen - press back or tap X to dismiss
echo "Dismissing premium upsell..."
input keyevent KEYCODE_BACK
sleep 3

# Step 4: Sign-up screen - tap X/close button (top right area)
# The X button is at approximately [891,170][1038,317]
echo "Dismissing sign-up screen..."
input tap 964 243
sleep 5

# Step 5: Main map view may show "Your map is ready" bottom sheet
# Tap X to close it - the X is on the right side of the bottom sheet
echo "Dismissing setup sheet if present..."
input tap 860 1510
sleep 3

# Step 6: Navigate to offline maps to queue a small map download
echo "Opening menu for offline maps..."
# Tap hamburger menu
input tap 972 333
sleep 3

# Check if we're on the menu - tap Offline maps
# Offline maps row is at approximately [42,564][1038,748]
input tap 540 656
sleep 5

# Tap "Add offline maps" button at bottom
# Button is at approximately [42,2122][1038,2295]
input tap 540 2208
sleep 5

# On the "Add offline maps" screen, tap the first small map (Afghanistan ~24MB or similar)
# Each row is clickable - tap center of first country row
# The first row (Afghanistan) is at approximately [0,747][1080,934]
input tap 540 840
sleep 3

# Also tap American Samoa row (1 MB) - much smaller
# Scroll down if needed or it should be visible
# American Samoa row is at approximately [0,1682][1080,1869]
input tap 540 1775
sleep 3

# Go back to main screen
input keyevent KEYCODE_BACK
sleep 3
input keyevent KEYCODE_BACK
sleep 3

# Wait for map download to complete (small maps ~1-24MB)
echo "Waiting for map downloads to complete..."
sleep 60

# Dismiss any "Your map is ready" sheet
input tap 860 1510
sleep 2

# Force stop to get clean state for tasks
am force-stop $PACKAGE
sleep 1

echo "=== Sygic GPS Navigation environment setup complete ==="
