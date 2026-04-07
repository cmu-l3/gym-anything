#!/system/bin/sh
# Post-start setup script for AndroidAPS environment
# This runs via: adb shell sh /sdcard/scripts/setup_androidaps.sh
#
# Responsibilities:
# 1. Verify APK installation
# 2. Grant Android permissions
# 3. Launch the app
# 4. Navigate through the Setup Wizard (Welcome -> EULA -> skip)
# 5. Dismiss red warning banners
# 6. Leave the app at the main overview screen

echo "=== Setting up AndroidAPS Environment ==="

# Wait for system to be fully ready
sleep 3

# Press Home to ensure we're at home screen
input keyevent KEYCODE_HOME
sleep 1

# Check if AndroidAPS is already installed (APK installed by runner via env.json apks field)
if pm list packages | grep -q "info.nightscout.androidaps"; then
    echo "AndroidAPS is installed"
else
    echo "Warning: AndroidAPS not installed - trying fallback install"
    if [ -f /sdcard/scripts/apks/androidaps-full-debug.apk ]; then
        pm install -r /sdcard/scripts/apks/androidaps-full-debug.apk
    fi
fi

# Grant ALL necessary Android permissions before launching (suppresses system dialogs)
echo "Granting permissions..."
pm grant info.nightscout.androidaps android.permission.ACCESS_FINE_LOCATION 2>/dev/null
pm grant info.nightscout.androidaps android.permission.ACCESS_COARSE_LOCATION 2>/dev/null
pm grant info.nightscout.androidaps android.permission.POST_NOTIFICATIONS 2>/dev/null
pm grant info.nightscout.androidaps android.permission.BLUETOOTH_CONNECT 2>/dev/null
pm grant info.nightscout.androidaps android.permission.BLUETOOTH_SCAN 2>/dev/null
pm grant info.nightscout.androidaps android.permission.NEARBY_WIFI_DEVICES 2>/dev/null
pm grant info.nightscout.androidaps android.permission.SYSTEM_ALERT_WINDOW 2>/dev/null
pm grant info.nightscout.androidaps android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS 2>/dev/null
pm grant info.nightscout.androidaps android.permission.READ_EXTERNAL_STORAGE 2>/dev/null
pm grant info.nightscout.androidaps android.permission.WRITE_EXTERNAL_STORAGE 2>/dev/null

# Disable battery optimization for AAPS (critical for pump communication)
dumpsys deviceidle whitelist +info.nightscout.androidaps 2>/dev/null

# Disable immersive mode confirmations
settings put secure immersive_mode_confirmations confirmed 2>/dev/null
settings put global policy_control "immersive.full=*" 2>/dev/null

# Launch AndroidAPS (correct activity: app.aaps.MainActivity)
echo "Launching AndroidAPS for first-time setup..."
am start -n info.nightscout.androidaps/app.aaps.MainActivity 2>/dev/null
sleep 5

# ================================================================
# Navigate through the Setup Wizard to complete first-run setup
# ================================================================
# On first launch, AndroidAPS shows the Setup Wizard.
# We navigate through it so subsequent launches go directly to the overview.
#
# UI coordinates based on 1080x2400 resolution (confirmed via uiautomator):
#   NEXT button:               bounds [807,2211][1038,2337] -> center (922, 2274)
#   I UNDERSTAND AND AGREE:    bounds [42,1090][1038,1216]  -> center (540, 1153)
#   Back arrow:                bounds [0,128][147,275]      -> center (73, 201)
#   Skip wizard OK button:     bounds [789,1332][957,1458]  -> center (873, 1395)

echo "Navigating Setup Wizard..."

# Step 1: Dismiss any notification permission dialog (tap Allow area)
# This dialog may or may not appear since we pre-granted POST_NOTIFICATIONS
input tap 540 856 2>/dev/null
sleep 1

# Step 2: Tap NEXT on Welcome page
echo "  Wizard: Tapping NEXT on Welcome page..."
input tap 922 2274
sleep 2

# Step 3: Tap "I UNDERSTAND AND AGREE" on EULA page
echo "  Wizard: Accepting EULA..."
input tap 540 1153
sleep 1

# Step 4: Tap NEXT after EULA acceptance
echo "  Wizard: Tapping NEXT after EULA..."
input tap 922 2274
sleep 2

# Step 5: On Permission page, tap back arrow to trigger "Skip setup wizard" dialog
echo "  Wizard: Skipping remaining wizard pages..."
input tap 73 201
sleep 1

# Step 6: Tap OK on "Skip setup wizard" confirmation dialog
echo "  Wizard: Confirming skip..."
input tap 873 1395
sleep 3

# ================================================================
# Dismiss red warning/notification banners on the overview
# ================================================================
# After skipping wizard, the overview shows several red warning banners.
# Scroll down to push them off-screen so the overview content is visible.
echo "Dismissing warning banners..."

# Scroll the notification area up to collapse warnings
input swipe 540 800 540 300 200
sleep 1
input swipe 540 800 540 300 200
sleep 1

# Press Home and relaunch to get a clean overview state
echo "Relaunching for clean state..."
input keyevent KEYCODE_HOME
sleep 1
am start -n info.nightscout.androidaps/app.aaps.MainActivity 2>/dev/null
sleep 3

echo "=== AndroidAPS setup completed ==="
echo "The Setup Wizard has been completed. Subsequent launches will go directly to the main overview."
