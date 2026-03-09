#!/bin/bash
set -euo pipefail

echo "=== Exporting teacher_onboarding_complete task result ==="

export DISPLAY=${DISPLAY:-:1}
RESULT_FILE="/tmp/task_result.txt"

WINDOW_TITLE=$(xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
echo "Window Title: $WINDOW_TITLE" > "$RESULT_FILE"

scrot /tmp/task_screenshot.png 2>/dev/null || true

echo "" >> "$RESULT_FILE"
echo "--- Staff: Jennifer Torres ---" >> "$RESULT_FILE"
mysql -u opensis_user -p'opensis_password_123' opensis -e \
    "SELECT staff_id, first_name, last_name, email, profile FROM staff WHERE first_name='Jennifer' AND last_name='Torres';" \
    >> "$RESULT_FILE" 2>/dev/null || echo "Query failed" >> "$RESULT_FILE"

echo "" >> "$RESULT_FILE"
echo "--- Course: SPAN301 ---" >> "$RESULT_FILE"
mysql -u opensis_user -p'opensis_password_123' opensis -e \
    "SELECT course_id, course_name, course_code, subject_area, grade_level, credits FROM courses WHERE course_code='SPAN301';" \
    >> "$RESULT_FILE" 2>/dev/null || true

echo "" >> "$RESULT_FILE"
echo "--- Placement Test Grades for Carlos/Ana ---" >> "$RESULT_FILE"
mysql -u opensis_user -p'opensis_password_123' opensis -e \
    "SELECT g.grade_id, s.first_name, s.last_name, c.course_code, g.assignment_name, g.grade_value
     FROM grades g
     INNER JOIN students s ON g.student_id = s.student_id
     INNER JOIN courses c ON g.course_id = c.course_id
     WHERE ((s.first_name='Carlos' AND s.last_name='Mendez') OR (s.first_name='Ana' AND s.last_name='Nguyen'))
       AND g.assignment_name = 'Placement Test'
     ORDER BY s.last_name;" \
    >> "$RESULT_FILE" 2>/dev/null || true

echo "=== Export complete ==="
echo "Result saved to: $RESULT_FILE"
