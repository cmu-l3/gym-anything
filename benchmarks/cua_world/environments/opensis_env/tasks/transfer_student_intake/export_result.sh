#!/bin/bash
set -euo pipefail

echo "=== Exporting transfer_student_intake task result ==="

export DISPLAY=${DISPLAY:-:1}
RESULT_FILE="/tmp/task_result.txt"

# Capture current window title
WINDOW_TITLE=$(xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
echo "Window Title: $WINDOW_TITLE" > "$RESULT_FILE"

# Capture screenshot as evidence
scrot /tmp/task_screenshot.png 2>/dev/null || true

# --- Zara Hoffman student record ---
echo "" >> "$RESULT_FILE"
echo "--- Student: Zara Hoffman ---" >> "$RESULT_FILE"
mysql -u opensis_user -p'opensis_password_123' opensis -e \
    "SELECT student_id, first_name, last_name, date_of_birth, gender, grade_level FROM students WHERE first_name='Zara' AND last_name='Hoffman';" \
    >> "$RESULT_FILE" 2>/dev/null || echo "Database query failed" >> "$RESULT_FILE"

# --- Courses ---
echo "" >> "$RESULT_FILE"
echo "--- Courses CHEM301, ENG401, HIST201 ---" >> "$RESULT_FILE"
mysql -u opensis_user -p'opensis_password_123' opensis -e \
    "SELECT course_id, course_name, course_code, subject_area, grade_level, credits FROM courses WHERE course_code IN ('CHEM301','ENG401','HIST201') ORDER BY course_code;" \
    >> "$RESULT_FILE" 2>/dev/null || true

# --- Grades for Zara Hoffman ---
echo "" >> "$RESULT_FILE"
echo "--- Grades for Zara Hoffman ---" >> "$RESULT_FILE"
mysql -u opensis_user -p'opensis_password_123' opensis -e \
    "SELECT g.grade_id, g.student_id, c.course_code, g.assignment_name, g.grade_value
     FROM grades g
     INNER JOIN students s ON g.student_id = s.student_id
     INNER JOIN courses c ON g.course_id = c.course_id
     WHERE s.first_name='Zara' AND s.last_name='Hoffman'
     ORDER BY c.course_code;" \
    >> "$RESULT_FILE" 2>/dev/null || true

echo "=== Export complete ==="
echo "Result saved to: $RESULT_FILE"
