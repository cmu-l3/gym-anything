#!/bin/bash
# Setup script for create_progress_note_template task

echo "=== Setting up Create Progress Note Template Task ==="

source /workspace/scripts/task_utils.sh

# Record initial database state
# Instead of guessing the exact table FreeMED uses for templates, we take a 
# schema-agnostic approach by dumping the DB and counting occurrences of our target phrases.
echo "Recording initial database state..."
mysqldump -u freemed -pfreemed freemed > /tmp/initial_dump.sql 2>/dev/null || true

# Count occurrences of the expected phrases (should be 0, but good to baseline)
COUNT_TITLE=$(grep -ci "Normal Physical Exam" /tmp/initial_dump.sql 2>/dev/null || echo "0")
COUNT_PHRASE1=$(grep -ci "in no acute distress" /tmp/initial_dump.sql 2>/dev/null || echo "0")
COUNT_PHRASE2=$(grep -ci "No murmurs, rubs, or gallops" /tmp/initial_dump.sql 2>/dev/null || echo "0")
COUNT_PHRASE3=$(grep -ci "clear to auscultation bilaterally" /tmp/initial_dump.sql 2>/dev/null || echo "0")

echo "$COUNT_TITLE" > /tmp/init_count_title.txt
echo "$COUNT_PHRASE1" > /tmp/init_count_phrase1.txt
echo "$COUNT_PHRASE2" > /tmp/init_count_phrase2.txt
echo "$COUNT_PHRASE3" > /tmp/init_count_phrase3.txt

# Record task start time
date +%s > /tmp/task_start_timestamp

# Ensure Firefox is running and focused on FreeMED
echo "Ensuring Firefox is running..."
ensure_firefox_running "http://localhost/freemed/"

# Focus Firefox window and maximize it
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_start_screenshot.png

echo "=== Create Progress Note Template Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Log in to FreeMED as admin (admin / admin)"
echo "  2. Navigate to the system template/macro editor"
echo "  3. Create a template named 'Normal Physical Exam'"
echo "  4. Paste the full clinical text body provided"
echo "  5. Save the template globally"
echo ""