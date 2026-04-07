#!/bin/bash
echo "=== Setting up add_employer task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 2

# Identify the exact employer table name (could vary slightly by FreeMED version)
EMPLOYER_TABLE=""
for tbl in employer employers empr; do
    if mysql -u freemed -pfreemed freemed -e "DESCRIBE $tbl" 2>/dev/null | grep -qi "name\|descrp\|ename"; then
        EMPLOYER_TABLE="$tbl"
        break
    fi
done

if [ -z "$EMPLOYER_TABLE" ]; then
    echo "WARNING: Could not identify employer table, trying fuzzy match..."
    EMPLOYER_TABLE=$(mysql -u freemed -pfreemed freemed -e "SHOW TABLES" 2>/dev/null | grep -i "employ" | head -1 || echo "")
fi

echo "Employer table identified as: ${EMPLOYER_TABLE:-unknown}"
echo "$EMPLOYER_TABLE" > /tmp/employer_table_name.txt

# Remove any pre-existing Meridian Logistics record to ensure a clean state
if [ -n "$EMPLOYER_TABLE" ]; then
    # Try multiple common column names; ignore errors if column doesn't exist
    for col in name ename employer_name emlname emname descrip; do
        mysql -u freemed -pfreemed freemed -e "DELETE FROM $EMPLOYER_TABLE WHERE LOWER($col) LIKE '%meridian%'" 2>/dev/null || true
    done
fi

# Record initial employer count
if [ -n "$EMPLOYER_TABLE" ]; then
    INITIAL_COUNT=$(mysql -u freemed -pfreemed freemed -N -e "SELECT COUNT(*) FROM $EMPLOYER_TABLE" 2>/dev/null || echo "0")
else
    INITIAL_COUNT="0"
fi
echo "$INITIAL_COUNT" > /tmp/initial_employer_count.txt
echo "Initial employer count: $INITIAL_COUNT"

# Ensure Apache is running
systemctl start apache2 2>/dev/null || service apache2 start 2>/dev/null || true
sleep 1

# Ensure Firefox is running and logged into FreeMED
ensure_firefox_running "http://localhost/freemed/"
sleep 5

# Wait for Firefox window and maximize it
wait_for_window "firefox\|mozilla\|FreeMED" 30
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial state screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="