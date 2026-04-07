#!/bin/bash
echo "=== Setting up update_registered_weapon_color task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Sarah Mitchell exists in NCIC Names
echo "Checking for Sarah Mitchell identity..."
SARAH_ID=$(opencad_db_query "SELECT id FROM ncic_names WHERE name='Sarah Mitchell' LIMIT 1")

if [ -z "$SARAH_ID" ]; then
    echo "Creating Sarah Mitchell identity..."
    opencad_db_query "INSERT INTO ncic_names (name, dob, gender, race, address, dl_status) VALUES ('Sarah Mitchell', '1995-05-12', 'Female', 'Caucasian', '123 Vinewood Blvd', 'Valid')"
    SARAH_ID=$(opencad_db_query "SELECT id FROM ncic_names WHERE name='Sarah Mitchell' LIMIT 1")
fi
echo "Sarah Mitchell ID: $SARAH_ID"

# 2. Reset the specific weapon state
# We delete any existing weapon with this serial to ensure a clean slate
echo "Resetting weapon state..."
opencad_db_query "DELETE FROM ncic_weapons WHERE serial_number='SM-9981'"

# Insert the weapon with the INITIAL color (Black)
# Fields: name_id, weapon_type, weapon_name, weapon_color, serial_number, wstatus
opencad_db_query "INSERT INTO ncic_weapons (name_id, weapon_type, weapon_name, weapon_color, serial_number, wstatus) VALUES ($SARAH_ID, 'Pistol', 'Combat Pistol', 'Black', 'SM-9981', 'Valid')"

# Verify setup
WEAPON_CHECK=$(opencad_db_query "SELECT weapon_color FROM ncic_weapons WHERE serial_number='SM-9981'")
echo "Weapon initialized with color: $WEAPON_CHECK"

# 3. Prepare Browser
# Remove Firefox profile locks and relaunch to ensure clean state
rm -f /home/ga/.mozilla/firefox/default-release/lock 2>/dev/null || true
pkill -9 -f firefox 2>/dev/null || true
sleep 2

echo "Launching Firefox..."
DISPLAY=:1 firefox "http://localhost/index.php" &
sleep 10

# Dismiss Firefox popups
DISPLAY=:1 wmctrl -c "Make the Firefox" 2>/dev/null || true
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Focus and maximize
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|OpenCAD" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="