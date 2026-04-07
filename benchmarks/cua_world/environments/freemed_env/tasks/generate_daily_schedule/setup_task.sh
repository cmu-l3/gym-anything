#!/bin/bash
echo "=== Setting up generate_daily_schedule task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents
rm -f /home/ga/Documents/daily_schedule.pdf

# Get today's date
TODAY=$(date +%Y-%m-%d)
echo "Seeding appointments for today ($TODAY)..."

# Seed the FreeMED database with patients and appointments for today
# 1. Insert dummy patients
freemed_query "INSERT IGNORE INTO patient (ptfname, ptlname) VALUES ('Robert', 'Chen');"
PID1=$(freemed_query "SELECT id FROM patient WHERE ptfname='Robert' AND ptlname='Chen' LIMIT 1;")

freemed_query "INSERT IGNORE INTO patient (ptfname, ptlname) VALUES ('Maria', 'Santos');"
PID2=$(freemed_query "SELECT id FROM patient WHERE ptfname='Maria' AND ptlname='Santos' LIMIT 1;")

freemed_query "INSERT IGNORE INTO patient (ptfname, ptlname) VALUES ('David', 'Washington');"
PID3=$(freemed_query "SELECT id FROM patient WHERE ptfname='David' AND ptlname='Washington' LIMIT 1;")

# 2. Clear any existing appointments for today to ensure a clean schedule
freemed_query "DELETE FROM scheduler WHERE caldateof='$TODAY';"

# 3. Schedule the patients for today
# We use caluser=1 (admin) to ensure they are visible
if [ -n "$PID1" ] && [ -n "$PID2" ] && [ -n "$PID3" ]; then
    freemed_query "INSERT INTO scheduler (caldateof, caltimeof, calpatient, caluser) VALUES ('$TODAY', '09:00:00', $PID1, 1);"
    freemed_query "INSERT INTO scheduler (caldateof, caltimeof, calpatient, caluser) VALUES ('$TODAY', '10:00:00', $PID2, 1);"
    freemed_query "INSERT INTO scheduler (caldateof, caltimeof, calpatient, caluser) VALUES ('$TODAY', '11:30:00', $PID3, 1);"
    echo "Successfully seeded 3 appointments for today."
else
    echo "WARNING: Failed to seed patients. IDs: $PID1, $PID2, $PID3"
fi

# Ensure Firefox is running and navigated to the login screen
ensure_firefox_running "http://localhost/freemed/"

# Focus and maximize the Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot for reference
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="