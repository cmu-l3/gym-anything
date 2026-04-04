#!/bin/bash
set -euo pipefail

echo "=== Exporting create_course task result ==="

export DISPLAY=${DISPLAY:-:1}
RESULT_FILE="/tmp/task_result.txt"

# Capture window title
WINDOW_TITLE=$(xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
echo "Window Title: $WINDOW_TITLE" > "$RESULT_FILE"

# Capture screenshot
scrot /tmp/task_screenshot.png 2>/dev/null || true

# Query database for the new course
echo "" >> "$RESULT_FILE"
echo "--- Database Query Result ---" >> "$RESULT_FILE"

mysql -u opensis_user -p'opensis_password_123' opensis -e \
    "SELECT course_id, course_name, course_code, subject_area, grade_level, credits FROM courses WHERE course_name LIKE '%Chemistry%' OR course_code='CHEM201';" \
    >> "$RESULT_FILE" 2>/dev/null || echo "Database query failed" >> "$RESULT_FILE"

# Get all courses
echo "" >> "$RESULT_FILE"
echo "--- All Courses ---" >> "$RESULT_FILE"
mysql -u opensis_user -p'opensis_password_123' opensis -e \
    "SELECT course_id, course_name, course_code FROM courses;" \
    >> "$RESULT_FILE" 2>/dev/null || true

echo "=== Export complete ==="
