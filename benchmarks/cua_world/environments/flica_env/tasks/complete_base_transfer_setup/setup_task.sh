#!/system/bin/sh
# Setup script for complete_base_transfer_setup task
# Resets all state so agent must configure everything from scratch.
#
# Expected start state after this script:
#   - App on Friends page, logged in as Friend/Family
#   - Display name: "CUA Suite" (default after clear)
#   - Position: Flight Attendant (default)
#   - Airports: default (empty or prior values cleared)
#   - Battery optimization: enabled (default/optimized)
#   - DND: off, no app exception

echo "=== Setting up complete_base_transfer_setup ==="

PACKAGE="com.robert.fcView"
TASK="complete_base_transfer_setup"

# ---- 1. Delete stale outputs from any previous run ----
rm -f /sdcard/${TASK}_result.json 2>/dev/null
rm -f /sdcard/${TASK}_final.png 2>/dev/null
rm -f /sdcard/ui_dump_${TASK}_*.xml 2>/dev/null
rm -f /sdcard/ui_tmp_${TASK}_*.xml 2>/dev/null
rm -f /sdcard/task_initial.png 2>/dev/null

# ---- 2. Record task start time ----
date +%s > /sdcard/task_start_time.txt

# ---- 3. Clear app data to reset profile to defaults ----
pm clear $PACKAGE 2>/dev/null
sleep 3

# ---- 4. Log in and land on Friends page ----
sh /sdcard/scripts/login_helper.sh 2>/dev/null
sleep 5

# After pm clear, the crew/friend selection may reappear after login_helper exits.
# Poll up to 3 times and tap Friend/Family if we're stuck on that screen.
for attempt in 1 2 3; do
    uiautomator dump /sdcard/login_verify.xml 2>/dev/null
    sleep 1
    if cat /sdcard/login_verify.xml 2>/dev/null | grep -q "Add New Friend"; then
        echo "On Friends page - login complete"
        break
    fi
    if cat /sdcard/login_verify.xml 2>/dev/null | grep -q "crewmember"; then
        echo "Retry $attempt: crew/friend selection still showing, tapping Friend/Family..."
        input tap 540 1650
        sleep 5
    fi
    if cat /sdcard/login_verify.xml 2>/dev/null | grep -q "Enter Your Name"; then
        echo "Retry $attempt: name entry showing, entering name..."
        input text "CUA Suite"
        sleep 1
        input tap 803 1023
        sleep 3
    fi
done
rm -f /sdcard/login_verify.xml 2>/dev/null

# ---- 5. Reset battery optimization to default (optimized) ----
echo "Resetting battery optimization..."
dumpsys deviceidle whitelist -$PACKAGE 2>/dev/null || true
cmd appops set $PACKAGE RUN_ANY_IN_BACKGROUND default 2>/dev/null || true
cmd appops set $PACKAGE RUN_IN_BACKGROUND default 2>/dev/null || true

# Verify cleanup
WHITELIST_CHECK=$(dumpsys deviceidle whitelist | grep "$PACKAGE" || echo "")
if [ -n "$WHITELIST_CHECK" ]; then
    echo "WARNING: Failed to remove package from whitelist"
else
    echo "Confirmed: Package NOT in battery whitelist (default state)"
fi

# ---- 6. Reset DND: off, no app exception ----
echo "Resetting DND state..."
settings put global zen_mode 0
cmd notification set_dnd off 2>/dev/null || true
cmd notification allow_dnd $PACKAGE false 2>/dev/null || true

# ---- 7. Capture initial screenshot ----
screencap -p /sdcard/task_initial.png 2>/dev/null

echo "=== Setup complete ==="
echo "State: profile=default, battery=optimized, DND=off"
echo "Agent must: set profile, harden device, send crew chat message"
