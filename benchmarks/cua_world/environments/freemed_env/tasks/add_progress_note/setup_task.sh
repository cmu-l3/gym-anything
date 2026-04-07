#!/bin/bash
echo "=== Setting up add_progress_note task ==="

# Record task start time (Anti-gaming check)
date +%s > /tmp/task_start_time.txt

# Source utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Ensure services are running
systemctl start mysql 2>/dev/null || service mysql start
systemctl start apache2 2>/dev/null || service apache2 start
sleep 2

# Verify patient Maria Santos exists
MARIA_ID=$(mysql -u freemed -pfreemed freemed -N -e "SELECT id FROM patient WHERE ptlname='Santos' AND ptfname='Maria' LIMIT 1" 2>/dev/null)
if [ -z "$MARIA_ID" ]; then
    echo "ERROR: Patient Maria Santos not found in database! Task cannot proceed correctly."
    exit 1
fi
echo "Patient Maria Santos found. ID: $MARIA_ID"
echo "$MARIA_ID" > /tmp/maria_patient_id.txt

# Locate the progress notes table (FreeMED versions vary, usually 'pnotes')
NOTES_TABLE=""
for tbl in pnotes progress_notes patient_notes; do
    EXISTS=$(mysql -u freemed -pfreemed freemed -N -e "SHOW TABLES LIKE '$tbl'" 2>/dev/null)
    if [ -n "$EXISTS" ]; then
        NOTES_TABLE="$tbl"
        break
    fi
done

if [ -n "$NOTES_TABLE" ]; then
    echo "$NOTES_TABLE" > /tmp/pnotes_table_name.txt
    INITIAL_PNOTES=$(mysql -u freemed -pfreemed freemed -N -e "SELECT COUNT(*) FROM $NOTES_TABLE" 2>/dev/null || echo "0")
    echo "$INITIAL_PNOTES" > /tmp/initial_pnotes_count.txt
    echo "Using notes table: $NOTES_TABLE (Initial count: $INITIAL_PNOTES)"
else
    echo "WARNING: Could not identify progress notes table."
    echo "0" > /tmp/initial_pnotes_count.txt
fi

# Ensure Firefox is running and logged in to FreeMED
FREEMED_URL="http://localhost/freemed/"
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$FREEMED_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
for i in {1..15}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|FreeMED"; then
        break
    fi
    sleep 1
done

# Focus and Maximize Firefox
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi
sleep 1

# Take initial screenshot to capture correct starting state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="