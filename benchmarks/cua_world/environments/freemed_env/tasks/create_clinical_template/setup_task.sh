#!/bin/bash
echo "=== Setting up Create Clinical Template task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for verification purposes
date +%s > /tmp/task_start_timestamp

# Dump database to check initial occurrences of the template text
mysqldump -u freemed -pfreemed freemed > /tmp/freemed_initial_dump.sql 2>/dev/null || true

# Count occurrences of the phrases using grep and wc -l (robust integer output)
INITIAL_HEENT_COUNT=$(grep -o "Normocephalic, atraumatic, PERRLA" /tmp/freemed_initial_dump.sql 2>/dev/null | wc -l)
INITIAL_CV_COUNT=$(grep -o "no murmurs, rubs, or gallops" /tmp/freemed_initial_dump.sql 2>/dev/null | wc -l)
INITIAL_TITLE_COUNT=$(grep -o "Normal Physical Exam" /tmp/freemed_initial_dump.sql 2>/dev/null | wc -l)

# Save counts for export script
echo "$INITIAL_HEENT_COUNT" > /tmp/initial_heent_count
echo "$INITIAL_CV_COUNT" > /tmp/initial_cv_count
echo "$INITIAL_TITLE_COUNT" > /tmp/initial_title_count

echo "Initial Counts recorded - HEENT: $INITIAL_HEENT_COUNT, CV: $INITIAL_CV_COUNT, Title: $INITIAL_TITLE_COUNT"

# Ensure Firefox is running and navigated to the correct start URL
ensure_firefox_running "http://localhost/freemed/"

# Maximize Firefox for better agent visibility
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take an initial screenshot proving we start from a clean slate
take_screenshot /tmp/task_template_start.png

echo "=== Setup complete ==="