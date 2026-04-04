#!/system/bin/sh
# Setup: Log in, send a friend request to 'ghost_pilot@example.com', return to home
set -e
echo "=== Setting up cancel_sent_request task ==="

# 1. Record task start time
date +%s > /sdcard/task_start_time.txt

# 2. Ensure clean login state using helper
sh /sdcard/scripts/login_helper.sh
sleep 5

# 3. Create the pending request (The "mess" the agent needs to clean up)
echo "Creating pending request for ghost_pilot@example.com..."

# Helper function to tap text on screen
tap_text() {
    local text="$1"
    uiautomator dump /sdcard/window_dump.xml >/dev/null
    # Extract bounds: [x1,y1][x2,y2]
    local bounds=$(grep "$text" /sdcard/window_dump.xml | sed -n 's/.*bounds="\([^"]*\)".*/\1/p' | head -n 1)
    
    if [ -n "$bounds" ]; then
        # Parse bounds to find center
        local x1=$(echo "$bounds" | sed 's/\[\([0-9]*\),[0-9]*\]\[[0-9]*\,[0-9]*\]/\1/')
        local y1=$(echo "$bounds" | sed 's/\[[0-9]*,\([0-9]*\)\]\[[0-9]*\,[0-9]*\]/\1/')
        local x2=$(echo "$bounds" | sed 's/\[[0-9]*\,[0-9]*\]\[\([0-9]*\),[0-9]*\]/\1/')
        local y2=$(echo "$bounds" | sed 's/\[[0-9]*\,[0-9]*\]\[[0-9]*,\([0-9]*\)\]/\1/')
        
        local center_x=$(( (x1 + x2) / 2 ))
        local center_y=$(( (y1 + y2) / 2 ))
        
        echo "Tapping '$text' at $center_x $center_y"
        input tap $center_x $center_y
        return 0
    else
        echo "Text '$text' not found"
        return 1
    fi
}

# Tap "Add Friend" or "+" button
# Try finding "Add Friend" text first
if ! tap_text "Add Friend"; then
    # Fallback to coordinate if text not found (approximate for bottom nav or FAB)
    echo "Using fallback tap for Add Friend..."
    input tap 950 2200 # Example FAB location
fi
sleep 3

# We should be on Add/Requests screen. 
# Depending on UI, might need to switch to "Add" tab or it might be default.
# Type the email
input text "ghost_pilot@example.com"
sleep 1

# Tap Send/Add button
# Look for "Send Request" or "Add"
if ! tap_text "Send Request"; then
    if ! tap_text "Add"; then
        # Fallback: Enter key
        input keyevent 66
    fi
fi
sleep 3

# Handle confirmation dialog if it appears (Dismiss/OK)
if tap_text "OK"; then
    sleep 1
fi
input keyevent KEYCODE_BACK # Dismiss keyboard if open
sleep 1
if tap_text "OK"; then
    sleep 1
fi

# 4. Return to Start State (Friends Home Page)
echo "Returning to Friends Home Page..."
# Press back until we see "Friends" or "My Crew" title, or just restart app to be safe
am force-stop com.robert.fcView
sleep 1
monkey -p com.robert.fcView -c android.intent.category.LAUNCHER 1 >/dev/null
sleep 8

# 5. Capture Initial State
echo "Capturing initial state..."
screencap -p /sdcard/task_initial.png
uiautomator dump /sdcard/initial_ui.xml >/dev/null

echo "=== Setup complete ==="