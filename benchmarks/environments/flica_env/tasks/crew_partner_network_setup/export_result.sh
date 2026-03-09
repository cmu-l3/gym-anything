#!/system/bin/sh
# Export script for crew_partner_network_setup task
# Navigates to Friends and Settings pages, dumps UI XML, checks for required content.

echo "=== Exporting crew_partner_network_setup result ==="

PACKAGE="com.robert.fcView"
TASK="crew_partner_network_setup"

screencap -p /sdcard/${TASK}_screenshot.png 2>/dev/null

# === Step 1: Navigate to Friends page via hamburger menu ===
input tap 1027 200
sleep 2
uiautomator dump /sdcard/ui_tmp_menu1.xml 2>/dev/null
sleep 1

LINE=$(grep -o 'content-desc="Friends"[^>]*bounds="[^"]*"' /sdcard/ui_tmp_menu1.xml 2>/dev/null | head -1)
if [ -n "$LINE" ]; then
    BOUNDS=$(echo "$LINE" | grep -o 'bounds="[^"]*"' | sed 's/bounds="//;s/"//')
    NUMS=$(echo $BOUNDS | sed 's/[][,]/ /g')
    set -- $NUMS
    if [ "$#" -ge 4 ]; then
        input tap $(( ($1 + $3) / 2 )) $(( ($2 + $4) / 2 ))
    else
        input tap 604 357
    fi
else
    input tap 604 357
fi
sleep 3

uiautomator dump /sdcard/ui_dump_${TASK}_friends.xml 2>/dev/null
sleep 1

# === Step 2: Navigate to Settings page via hamburger menu ===
input tap 1027 200
sleep 2
uiautomator dump /sdcard/ui_tmp_menu2.xml 2>/dev/null
sleep 1

LINE=$(grep -o 'content-desc="Settings"[^>]*bounds="[^"]*"' /sdcard/ui_tmp_menu2.xml 2>/dev/null | head -1)
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

uiautomator dump /sdcard/ui_dump_${TASK}_settings.xml 2>/dev/null
sleep 1

# === Step 3: Check display name - look for distinctive keyword ===
DISPLAY_NAME_FOUND=0
if grep -qi 'Rodriguez' /sdcard/ui_dump_${TASK}_settings.xml 2>/dev/null; then
    DISPLAY_NAME_FOUND=1
fi

# Check position set to Captain
POSITION_FOUND=0
if grep -qi 'Captain' /sdcard/ui_dump_${TASK}_settings.xml 2>/dev/null; then
    POSITION_FOUND=1
fi

# === Step 3: Expand HOME & BASE AIRPORTS to check airport codes ===
# Navigate back to Settings, scroll to HOME & BASE AIRPORTS, expand it, dump XML
input tap 1027 200
sleep 2
uiautomator dump /sdcard/ui_tmp_menu3.xml 2>/dev/null
sleep 1

# Find and tap Settings in menu
LINE=$(grep -o 'content-desc="Settings"[^>]*bounds="[^"]*"' /sdcard/ui_tmp_menu3.xml 2>/dev/null | head -1)
if [ -n "$LINE" ]; then
    BOUNDS=$(echo "$LINE" | grep -o 'bounds="[^"]*"' | sed 's/bounds="//;s/"//')
    X1=$(echo $BOUNDS | sed 's/\[//;s/,.*//')
    Y1=$(echo $BOUNDS | sed 's/.*,//;s/\].*//')
    X2=$(echo $BOUNDS | sed 's/.*\]\[//;s/,.*//')
    Y2=$(echo $BOUNDS | sed 's/.*,\([0-9]*\)\].*/\1/')
    CX=$(( (X1 + X2) / 2 ))
    CY=$(( (Y1 + Y2) / 2 ))
    input tap $CX $CY
else
    input tap 604 863
fi
sleep 3

# Scroll down to HOME & BASE AIRPORTS section (need 5-6 scrolls from top)
for i in 1 2 3 4 5 6; do
    input swipe 540 1500 540 900 300
    sleep 0.5
done

# Dump XML to check for HOME & BASE AIRPORTS section
uiautomator dump /sdcard/ui_tmp_airports_scroll.xml 2>/dev/null
sleep 1

# Find HOME & BASE AIRPORTS section and tap it
LINE=$(grep -o 'content-desc="HOME [^"]*AIRPORTS"[^>]*bounds="[^"]*"' /sdcard/ui_tmp_airports_scroll.xml 2>/dev/null | head -1)
if [ -n "$LINE" ]; then
    BOUNDS=$(echo "$LINE" | grep -o 'bounds="[^"]*"' | sed 's/bounds="//;s/"//')
    NUMS=$(echo $BOUNDS | sed 's/[][,]/ /g')
    set -- $NUMS
    if [ "$#" -ge 4 ]; then
        CX=$(( ($1 + $3) / 2 ))
        CY=$(( ($2 + $4) / 2 ))
        input tap $CX $CY
        sleep 3
    fi
fi

# Dump XML after expansion
uiautomator dump /sdcard/ui_dump_${TASK}_airports.xml 2>/dev/null
sleep 1

# Check for airport codes in expanded XML
HOME_AIRPORT_FOUND=0
BASE_AIRPORT_FOUND=0
if grep -q 'ORD' /sdcard/ui_dump_${TASK}_airports.xml 2>/dev/null; then
    HOME_AIRPORT_FOUND=1
fi
if grep -q 'ORD' /sdcard/ui_dump_${TASK}_airports.xml 2>/dev/null; then
    BASE_AIRPORT_FOUND=1
fi


# === Friends check ===

# Check friend1: fo.james
FRIEND1_FOUND=0
if grep -qi 'fo.james' /sdcard/ui_dump_${TASK}_friends.xml 2>/dev/null; then
    FRIEND1_FOUND=1
fi
# Check friend2: fa.chen
FRIEND2_FOUND=0
if grep -qi 'fa.chen' /sdcard/ui_dump_${TASK}_friends.xml 2>/dev/null; then
    FRIEND2_FOUND=1
fi
# Check friend3: fa.garcia
FRIEND3_FOUND=0
if grep -qi 'fa.garcia' /sdcard/ui_dump_${TASK}_friends.xml 2>/dev/null; then
    FRIEND3_FOUND=1
fi

# === Reachability checks ===
SETTINGS_REACHABLE=0
FRIENDS_REACHABLE=0
if [ -s /sdcard/ui_dump_${TASK}_settings.xml ]; then SETTINGS_REACHABLE=1; fi
if [ -s /sdcard/ui_dump_${TASK}_friends.xml ]; then FRIENDS_REACHABLE=1; fi

# === Write result JSON ===
cat > /sdcard/${TASK}_result.json << JSONEOF
{
    "display_name_found": $DISPLAY_NAME_FOUND,
    "position_found": $POSITION_FOUND,
    "home_airport_found": $HOME_AIRPORT_FOUND,
    "base_airport_found": $BASE_AIRPORT_FOUND,
    "friend1_found": $FRIEND1_FOUND,
    "friend2_found": $FRIEND2_FOUND,
    "friend3_found": $FRIEND3_FOUND,
    "settings_reachable": $SETTINGS_REACHABLE,
    "friends_reachable": $FRIENDS_REACHABLE
}
JSONEOF

echo "Display name [Rodriguez]: $DISPLAY_NAME_FOUND"
echo "=== Export Complete ==="
