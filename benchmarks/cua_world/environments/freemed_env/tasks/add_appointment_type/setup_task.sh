#!/bin/bash
# Setup script for Configure Appointment Type task

echo "=== Setting up Configure Appointment Type Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# ================================================================
# DB CLEANUP & INITIAL STATE RECORDING
# ================================================================
echo "Ensuring a clean state (removing any existing matching records)..."
DUMP_FILE="/tmp/freemed_clean.sql"
mysqldump -u freemed -pfreemed freemed --skip-extended-insert > "$DUMP_FILE" 2>/dev/null

# Find tables containing the target string to wipe them dynamically
TABLES_TO_CLEAN=$(grep -i "Weight Management Consult" "$DUMP_FILE" | grep -oP 'INSERT INTO `\K[^`]+' | sort | uniq || true)
for table in $TABLES_TO_CLEAN; do
    COLS=$(mysql -u freemed -pfreemed -N -e "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='freemed' AND TABLE_NAME='$table' AND DATA_TYPE IN ('varchar','text','char')")
    for col in $COLS; do
        mysql -u freemed -pfreemed freemed -e "DELETE FROM \`$table\` WHERE \`$col\` LIKE '%Weight Management Consult%'" 2>/dev/null || true
    done
done

# Record exact row count of the entire database (counts all INSERT statements)
echo "Recording initial database state..."
mysqldump -u freemed -pfreemed freemed --skip-extended-insert > "/tmp/freemed_initial_dump.sql" 2>/dev/null
INITIAL_TOTAL_ROWS=$(grep -c "^INSERT INTO" "/tmp/freemed_initial_dump.sql" || echo "0")
echo "$INITIAL_TOTAL_ROWS" > /tmp/initial_db_rows.txt
echo "Initial total DB rows: $INITIAL_TOTAL_ROWS"

# ================================================================
# UI INITIALIZATION
# ================================================================
echo "Ensuring Firefox is running and focused on FreeMED..."
FREEMED_URL="http://localhost/freemed/"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$FREEMED_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
wait_for_window "firefox\|mozilla\|FreeMED" 30 || echo "WARNING: Firefox window not detected"

# Ensure desktop is active and focus Firefox
echo "Selecting desktop and focusing browser..."
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" || true
sleep 0.5

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize window
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Log in to FreeMED (Username: admin, Password: admin)"
echo "  2. Navigate to System / Support Data"
echo "  3. Open Appointment Types (or Visit/Schedule Types)"
echo "  4. Add a new type:"
echo "     - Name: Weight Management Consult"
echo "     - Duration: 45 minutes"
echo "  5. Save the configuration"
echo ""