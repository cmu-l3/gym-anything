#!/system/bin/sh
# Helper script to log into Flight Crew View from any state.
# Called by task setup scripts that need the app in a logged-in state.
# Uses pre-created account: cuasuite@gmail.com / #Aa123456aA
#
# This script handles multiple scenarios:
# A) App data cleared -> full welcome/login flow
# B) App already logged in -> goes directly to Friends page
# C) App at crew/friend selection -> taps Friend/Family
#
# Ends on the Friends page (home screen for Friend/Family users).

PACKAGE="com.robert.fcView"

echo "=== Flight Crew View Login Helper ==="

# Force stop to get clean state
am force-stop $PACKAGE
sleep 2

# Launch app
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
echo "Waiting for app to load..."
sleep 10

# Check what screen we're on by dumping UI
uiautomator dump /sdcard/login_check.xml 2>/dev/null
sleep 1

# Read the UI dump to determine current screen
UI_CONTENT=""
if [ -f /sdcard/login_check.xml ]; then
    UI_CONTENT=$(cat /sdcard/login_check.xml)
fi

# --- Scenario: Already on Friends page ---
if echo "$UI_CONTENT" | grep -q "Friends"; then
    if echo "$UI_CONTENT" | grep -q "Add New Friend"; then
        echo "Already on Friends page - done!"
        rm -f /sdcard/login_check.xml
        exit 0
    fi
fi

# --- Scenario: At crew/friend selection screen ---
if echo "$UI_CONTENT" | grep -q "crewmember"; then
    echo "At crew/friend selection - tapping Friend/Family..."
    input tap 540 1650
    sleep 3
    # Handle name entry if it appears
    uiautomator dump /sdcard/login_check2.xml 2>/dev/null
    sleep 1
    if [ -f /sdcard/login_check2.xml ]; then
        if cat /sdcard/login_check2.xml | grep -q "Enter Your Name"; then
            input text "CUA Suite"
            sleep 1
            input tap 803 1023
            sleep 3
        fi
    fi
    rm -f /sdcard/login_check.xml /sdcard/login_check2.xml
    echo "Should be on Friends page now"
    exit 0
fi

# --- Scenario: Welcome screen (checkbox + Continue) ---
# Check for the welcome screen with privacy policy checkbox
if echo "$UI_CONTENT" | grep -q "Let"; then
    echo "At welcome screen - accepting terms..."
    # Tap checkbox area
    input tap 150 1375
    sleep 1
    # Tap Continue
    input tap 540 1567
    sleep 3
fi

# --- Scenario: Login/Create Account screen ---
# Check current screen again after potential navigation
uiautomator dump /sdcard/login_check.xml 2>/dev/null
sleep 1
if [ -f /sdcard/login_check.xml ]; then
    UI_CONTENT=$(cat /sdcard/login_check.xml)
fi

if echo "$UI_CONTENT" | grep -q "LOG IN"; then
    echo "At login screen - entering credentials..."

    # Make sure we're on LOG IN tab (not CREATE ACCOUNT)
    # LOG IN tab bounds are approximately [42,666][540,792]
    input tap 291 729
    sleep 1

    # Tap Email field
    input tap 540 1304
    sleep 1

    # Type email
    input text "cuasuite@gmail.com"
    sleep 0.5

    # Tab to password field
    input keyevent KEYCODE_TAB
    sleep 0.5

    # Type password (# is %23 for adb input)
    input text '%23Aa123456aA'
    sleep 0.5

    # Dismiss keyboard
    input keyevent KEYCODE_BACK
    sleep 1

    # Tap LOG IN button
    input tap 540 1540
    sleep 5

    # Check what screen we're on now
    uiautomator dump /sdcard/login_check.xml 2>/dev/null
    sleep 1
    if [ -f /sdcard/login_check.xml ]; then
        UI_CONTENT=$(cat /sdcard/login_check.xml)
    fi

    # Handle crew/friend selection if it appears
    if echo "$UI_CONTENT" | grep -q "crewmember"; then
        echo "At crew/friend selection - tapping Friend/Family..."
        input tap 540 1650
        sleep 3

        # Handle name entry if it appears
        uiautomator dump /sdcard/login_check2.xml 2>/dev/null
        sleep 1
        if [ -f /sdcard/login_check2.xml ]; then
            if cat /sdcard/login_check2.xml | grep -q "Enter Your Name"; then
                input text "CUA Suite"
                sleep 1
                input tap 803 1023
                sleep 3
            fi
        fi
        rm -f /sdcard/login_check2.xml
    fi
fi

# Cleanup temp files
rm -f /sdcard/login_check.xml /sdcard/login_check2.xml

# Final wait for app to settle
sleep 2

# Dismiss any keyboard that might be showing
input keyevent KEYCODE_BACK
sleep 1

echo "=== Login Helper completed ==="
echo "App should be on the Friends page (home screen)"
