#!/system/bin/sh
# Setup script for set_temp_target task
#
# Precondition: The post_start hook (setup_androidaps.sh) has already
# completed the Setup Wizard, so the app goes directly to the overview.
#
# This script ensures AndroidAPS is on the main overview screen,
# ready for the agent to set a temporary target.

echo "=== Setting up set_temp_target task ==="

# Go to home screen first (clean state)
input keyevent KEYCODE_HOME
sleep 1

# Force-stop and relaunch to ensure fresh start on overview
am force-stop info.nightscout.androidaps 2>/dev/null
sleep 1

# Launch AndroidAPS - goes directly to main overview (wizard already completed)
echo "Launching AndroidAPS..."
am start -n info.nightscout.androidaps/app.aaps.MainActivity 2>/dev/null
sleep 5

# Dismiss any residual notification dialog (tap Allow area, harmless if none)
input tap 540 856 2>/dev/null
sleep 1

# Scroll down slightly to push any remaining red warning banners up
input swipe 540 800 540 400 200
sleep 1

# Verify CGM data reference is available
if [ -f /sdcard/data/cgm_data/dexcom_cgm_export.csv ]; then
    echo "Real Dexcom CGM data available (10000+ glucose readings from Dexcom G6)"
fi

echo "=== Task setup completed ==="
echo "AndroidAPS main overview is visible."
echo "Agent should set a Temp Target: 140 mg/dL for 60 minutes (Exercise)."
