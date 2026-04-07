#!/system/bin/sh
# Export script for complete_base_transfer_setup task
# Collects both app UI state (via XML dumps) and Android system state
# (via dumpsys/settings) into a single result JSON.

echo "=== Exporting complete_base_transfer_setup results ==="

PACKAGE="com.robert.fcView"
TASK="complete_base_transfer_setup"

# ---- Final screenshot ----
screencap -p /sdcard/${TASK}_final.png 2>/dev/null

# =====================================================
# PART 1: App UI state — profile and settings checks
# =====================================================

# Navigate to Settings via hamburger menu
input tap 1027 200
sleep 2
uiautomator dump /sdcard/ui_tmp_${TASK}_menu1.xml 2>/dev/null
sleep 1

# Tap Settings
LINE=$(grep -o 'content-desc="Settings"[^>]*bounds="[^"]*"' /sdcard/ui_tmp_${TASK}_menu1.xml 2>/dev/null | head -1)
if [ -n "$LINE" ]; then
    BOUNDS=$(echo "$LINE" | grep -o 'bounds="[^"]*"' | sed 's/bounds="//;s/"//')
    NUMS=$(echo $BOUNDS | sed 's/[][,]/ /g')
    set -- $NUMS
    if [ "$#" -ge 4 ]; then
        input tap $(( ($1 + $3) / 2 )) $(( ($2 + $4) / 2 ))
    else
        input tap 604 863
    fi
else
    input tap 604 863
fi
sleep 3

# Dump top of Settings (display name, position)
uiautomator dump /sdcard/ui_dump_${TASK}_settings.xml 2>/dev/null
sleep 1

# Check display name contains "Rodriguez" AND "LAX"
DISPLAY_NAME_FOUND=0
if grep -qi 'Rodriguez' /sdcard/ui_dump_${TASK}_settings.xml 2>/dev/null; then
    if grep -qi 'LAX' /sdcard/ui_dump_${TASK}_settings.xml 2>/dev/null; then
        DISPLAY_NAME_FOUND=1
    fi
fi

# Check position is Captain
POSITION_FOUND=0
if grep -qi 'Captain' /sdcard/ui_dump_${TASK}_settings.xml 2>/dev/null; then
    POSITION_FOUND=1
fi

# ---- Scroll to HOME & BASE AIRPORTS section ----
# Need 5-6 scrolls from top of Settings to reach it
for i in 1 2 3 4 5 6; do
    input swipe 540 1500 540 900 300
    sleep 0.5
done

uiautomator dump /sdcard/ui_tmp_${TASK}_scroll.xml 2>/dev/null
sleep 1

# Find and tap HOME & BASE AIRPORTS to expand it
LINE=$(grep -o 'content-desc="HOME [^"]*AIRPORTS"[^>]*bounds="[^"]*"' /sdcard/ui_tmp_${TASK}_scroll.xml 2>/dev/null | head -1)
if [ -n "$LINE" ]; then
    BOUNDS=$(echo "$LINE" | grep -o 'bounds="[^"]*"' | sed 's/bounds="//;s/"//')
    NUMS=$(echo $BOUNDS | sed 's/[][,]/ /g')
    set -- $NUMS
    if [ "$#" -ge 4 ]; then
        input tap $(( ($1 + $3) / 2 )) $(( ($2 + $4) / 2 ))
        sleep 3
    fi
fi

# Dump expanded airports section
uiautomator dump /sdcard/ui_dump_${TASK}_airports.xml 2>/dev/null
sleep 1

# Check for LAX in airport fields
HOME_AIRPORT_FOUND=0
BASE_AIRPORT_FOUND=0

# Look for Home Airport entry containing LAX
if grep -q 'Home Airport' /sdcard/ui_dump_${TASK}_airports.xml 2>/dev/null; then
    if grep -q 'LAX' /sdcard/ui_dump_${TASK}_airports.xml 2>/dev/null; then
        HOME_AIRPORT_FOUND=1
    fi
fi

# For base airport, check more specifically
if grep -q 'Base.*Airport' /sdcard/ui_dump_${TASK}_airports.xml 2>/dev/null; then
    if grep -q 'LAX' /sdcard/ui_dump_${TASK}_airports.xml 2>/dev/null; then
        BASE_AIRPORT_FOUND=1
    fi
fi

# =====================================================
# PART 2: Android system state checks
# =====================================================

# Battery whitelist check
IS_WHITELISTED=0
if dumpsys deviceidle whitelist | grep -q "$PACKAGE"; then
    IS_WHITELISTED=1
fi

# DND zen mode check (0=off, 1/2/3=on)
ZEN_MODE=$(settings get global zen_mode)
DND_ENABLED=0
if [ "$ZEN_MODE" != "0" ]; then
    DND_ENABLED=1
fi

# DND app exception check
DND_EXCEPTION=0
POLICY_DUMP=$(dumpsys notification policy 2>/dev/null)
if echo "$POLICY_DUMP" | grep -q "package=$PACKAGE"; then
    DND_EXCEPTION=1
fi
# Also check channel-level bypass
NOTIF_DUMP=$(dumpsys notification 2>/dev/null)
CHANNEL_BYPASS=0
if echo "$NOTIF_DUMP" | grep -A 20 "pkg=$PACKAGE" | grep -q "bypassDnd=true"; then
    CHANNEL_BYPASS=1
fi

# =====================================================
# PART 3: Crew Chat message check
# =====================================================

# Navigate back from Settings to app main screen using Back button
input tap 73 200
sleep 2

# Open hamburger menu to navigate to Crew Chat
input tap 1027 200
sleep 2
uiautomator dump /sdcard/ui_tmp_${TASK}_chatmenu.xml 2>/dev/null
sleep 1

# Tap Crew Chat from menu
LINE=$(grep -o 'content-desc="Crew Chat"[^>]*bounds="[^"]*"' /sdcard/ui_tmp_${TASK}_chatmenu.xml 2>/dev/null | head -1)
if [ -n "$LINE" ]; then
    BOUNDS=$(echo "$LINE" | grep -o 'bounds="[^"]*"' | sed 's/bounds="//;s/"//')
    NUMS=$(echo $BOUNDS | sed 's/[][,]/ /g')
    set -- $NUMS
    if [ "$#" -ge 4 ]; then
        input tap $(( ($1 + $3) / 2 )) $(( ($2 + $4) / 2 ))
    fi
fi
sleep 3

uiautomator dump /sdcard/ui_dump_${TASK}_chat.xml 2>/dev/null
sleep 1

CHAT_MSG_FOUND=0
if grep -qi 'reporting for duty' /sdcard/ui_dump_${TASK}_chat.xml 2>/dev/null; then
    CHAT_MSG_FOUND=1
fi

# =====================================================
# PART 4: Check if app is in foreground
# =====================================================
APP_FOREGROUND=0
if dumpsys window windows | grep -E 'mCurrentFocus|mFocusedApp' | grep -q "$PACKAGE"; then
    APP_FOREGROUND=1
fi

# Check if Settings was visited during the session
SETTINGS_VISITED=0
if dumpsys activity recents | grep -qi "com.android.settings"; then
    SETTINGS_VISITED=1
fi

# =====================================================
# Write result JSON
# =====================================================
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

cat > /sdcard/${TASK}_result.json << JSONEOF
{
    "display_name_found": $DISPLAY_NAME_FOUND,
    "position_found": $POSITION_FOUND,
    "home_airport_found": $HOME_AIRPORT_FOUND,
    "base_airport_found": $BASE_AIRPORT_FOUND,
    "battery_whitelisted": $IS_WHITELISTED,
    "dnd_enabled": $DND_ENABLED,
    "dnd_exception": $DND_EXCEPTION,
    "dnd_channel_bypass": $CHANNEL_BYPASS,
    "zen_mode": "$ZEN_MODE",
    "chat_message_found": $CHAT_MSG_FOUND,
    "app_foreground": $APP_FOREGROUND,
    "settings_visited": $SETTINGS_VISITED,
    "task_start": $TASK_START,
    "task_end": $TASK_END
}
JSONEOF

echo "=== Export complete ==="
cat /sdcard/${TASK}_result.json
