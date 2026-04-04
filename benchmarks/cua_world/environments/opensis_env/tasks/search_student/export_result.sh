#!/bin/bash
set -euo pipefail

echo "=== Exporting search_student task result ==="

export DISPLAY=${DISPLAY:-:1}
RESULT_FILE="/tmp/task_result.txt"

WINDOW_TITLE=$(xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
echo "Window Title: $WINDOW_TITLE" > "$RESULT_FILE"

scrot /tmp/task_screenshot.png 2>/dev/null || true

# Verify student exists in database (for reference)
echo "" >> "$RESULT_FILE"
echo "--- Student in Database ---" >> "$RESULT_FILE"
mysql -u opensis_user -p'opensis_password_123' opensis -e \
    "SELECT * FROM students WHERE first_name='Sample' AND last_name='Student';" \
    >> "$RESULT_FILE" 2>/dev/null || echo "Database query failed" >> "$RESULT_FILE"

echo "=== Export complete ==="
