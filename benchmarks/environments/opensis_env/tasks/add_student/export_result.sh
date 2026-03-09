#!/bin/bash
set -euo pipefail

echo "=== Exporting add_student task result ==="

export DISPLAY=${DISPLAY:-:1}
RESULT_FILE="/tmp/task_result.txt"

# Capture current window title
WINDOW_TITLE=$(xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
echo "Window Title: $WINDOW_TITLE" > "$RESULT_FILE"

# Capture screenshot as evidence
scrot /tmp/task_screenshot.png 2>/dev/null || true

# Query database for the new student
echo "" >> "$RESULT_FILE"
echo "--- Database Query Result ---" >> "$RESULT_FILE"

# Check if the student was added to the database
mysql -u opensis_user -p'opensis_password_123' opensis -e \
    "SELECT student_id, first_name, last_name, date_of_birth, gender, grade_level, created_at FROM students WHERE first_name='Emily' AND last_name='Johnson';" \
    >> "$RESULT_FILE" 2>/dev/null || echo "Database query failed" >> "$RESULT_FILE"

# Also get total student count
echo "" >> "$RESULT_FILE"
echo "--- Total Students ---" >> "$RESULT_FILE"
mysql -u opensis_user -p'opensis_password_123' opensis -e \
    "SELECT COUNT(*) as total_students FROM students;" \
    >> "$RESULT_FILE" 2>/dev/null || true

# Get latest student record
echo "" >> "$RESULT_FILE"
echo "--- Latest Student Record ---" >> "$RESULT_FILE"
mysql -u opensis_user -p'opensis_password_123' opensis -e \
    "SELECT * FROM students ORDER BY student_id DESC LIMIT 1;" \
    >> "$RESULT_FILE" 2>/dev/null || true

echo "=== Export complete ==="
echo "Result saved to: $RESULT_FILE"
