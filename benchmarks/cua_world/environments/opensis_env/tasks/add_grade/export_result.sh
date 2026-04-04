#!/bin/bash
set -euo pipefail

echo "=== Exporting add_grade task result ==="

export DISPLAY=${DISPLAY:-:1}
RESULT_FILE="/tmp/task_result.txt"

WINDOW_TITLE=$(xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
echo "Window Title: $WINDOW_TITLE" > "$RESULT_FILE"

scrot /tmp/task_screenshot.png 2>/dev/null || true

echo "" >> "$RESULT_FILE"
echo "--- Grade Records ---" >> "$RESULT_FILE"

mysql -u opensis_user -p'opensis_password_123' opensis -e \
    "SELECT g.grade_id, s.first_name, s.last_name, c.course_name, g.assignment_name, g.grade_value
     FROM grades g
     JOIN students s ON g.student_id = s.student_id
     JOIN courses c ON g.course_id = c.course_id
     ORDER BY g.grade_id DESC LIMIT 10;" \
    >> "$RESULT_FILE" 2>/dev/null || echo "Database query failed" >> "$RESULT_FILE"

echo "" >> "$RESULT_FILE"
echo "--- Sample Student's Grades ---" >> "$RESULT_FILE"
mysql -u opensis_user -p'opensis_password_123' opensis -e \
    "SELECT g.*, c.course_name FROM grades g
     JOIN students s ON g.student_id = s.student_id
     JOIN courses c ON g.course_id = c.course_id
     WHERE s.first_name='Sample' AND s.last_name='Student';" \
    >> "$RESULT_FILE" 2>/dev/null || true

echo "=== Export complete ==="
