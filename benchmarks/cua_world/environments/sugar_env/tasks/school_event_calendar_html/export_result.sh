#!/bin/bash
echo "=== Exporting school_event_calendar_html task result ==="

# Take final screenshot
su - ga -c "DISPLAY=:1 scrot /tmp/task_final.png" 2>/dev/null || DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

PY_FILE="/home/ga/Documents/generate_calendar.py"
HTML_FILE="/home/ga/Documents/school_calendar.html"
TASK_START=$(cat /tmp/calendar_task_start_ts 2>/dev/null || echo "0")

PY_EXISTS="false"
PY_SIZE=0
PY_MTIME=0
PY_MODIFIED="false"

HTML_EXISTS="false"
HTML_SIZE=0
HTML_MTIME=0
HTML_MODIFIED="false"

# Validate and capture the Python script file
if [ -f "$PY_FILE" ]; then
    PY_EXISTS="true"
    PY_SIZE=$(stat --format=%s "$PY_FILE" 2>/dev/null || echo "0")
    PY_MTIME=$(stat --format=%Y "$PY_FILE" 2>/dev/null || echo "0")
    if [ "$PY_MTIME" -gt "$TASK_START" ]; then
        PY_MODIFIED="true"
    fi
    cp "$PY_FILE" /tmp/generate_calendar.py
    chmod 666 /tmp/generate_calendar.py
fi

# Validate and capture the HTML output file
if [ -f "$HTML_FILE" ]; then
    HTML_EXISTS="true"
    HTML_SIZE=$(stat --format=%s "$HTML_FILE" 2>/dev/null || echo "0")
    HTML_MTIME=$(stat --format=%Y "$HTML_FILE" 2>/dev/null || echo "0")
    if [ "$HTML_MTIME" -gt "$TASK_START" ]; then
        HTML_MODIFIED="true"
    fi
    cp "$HTML_FILE" /tmp/school_calendar.html
    chmod 666 /tmp/school_calendar.html
fi

# Compile metadata onto JSON payload for the external verifier
cat > /tmp/calendar_task_result.json << EOF
{
    "py_exists": $PY_EXISTS,
    "py_size": $PY_SIZE,
    "py_modified": $PY_MODIFIED,
    "html_exists": $HTML_EXISTS,
    "html_size": $HTML_SIZE,
    "html_modified": $HTML_MODIFIED
}
EOF

chmod 666 /tmp/calendar_task_result.json
echo "Result saved to /tmp/calendar_task_result.json"
cat /tmp/calendar_task_result.json
echo "=== Export complete ==="