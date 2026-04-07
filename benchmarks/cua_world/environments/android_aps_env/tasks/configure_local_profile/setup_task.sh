#!/system/bin/sh
# Setup script for configure_local_profile task
#
# Precondition: The post_start hook (setup_androidaps.sh) has already
# completed the Setup Wizard, so the app goes directly to the overview.
#
# This script ensures AndroidAPS is on the main overview screen with
# "NO PROFILE SET" visible, ready for the agent to navigate to the
# PROFILE tab and configure the Local Profile.

echo "=== Setting up configure_local_profile task ==="

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

# Scroll down slightly to push any remaining red warning banners up,
# exposing the overview content (NO PROFILE SET, glucose graph, tabs)
input swipe 540 800 540 400 200
sleep 1

# Reference: Clinical profile data is at /sdcard/data/profiles/clinical_profile.json
if [ -f /sdcard/data/profiles/clinical_profile.json ]; then
    echo "Clinical profile data available at /sdcard/data/profiles/clinical_profile.json"
fi

echo "=== Task setup completed ==="
echo "AndroidAPS main overview is visible with NO PROFILE SET."
echo "Agent should tap PROFILE tab and configure DIA, IC, ISF, BAS, TARG values."
