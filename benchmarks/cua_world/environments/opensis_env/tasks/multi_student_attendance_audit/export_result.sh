#!/bin/bash
set -euo pipefail

echo "=== Exporting multi_student_attendance_audit task result ==="

export DISPLAY=${DISPLAY:-:1}
RESULT_FILE="/tmp/task_result.txt"

WINDOW_TITLE=$(xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
echo "Window Title: $WINDOW_TITLE" > "$RESULT_FILE"

scrot /tmp/task_screenshot.png 2>/dev/null || true

echo "" >> "$RESULT_FILE"
echo "--- Attendance Records for 2024-11-04 ---" >> "$RESULT_FILE"
mysql -u opensis_user -p'opensis_password_123' opensis -e \
    "SELECT a.attendance_id, s.first_name, s.last_name, a.attendance_date, a.status
     FROM attendance a
     INNER JOIN students s ON a.student_id = s.student_id
     WHERE a.attendance_date = '2024-11-04'
       AND s.first_name IN ('Miguel','Aisha','Dmitri')
       AND s.last_name IN ('Santos','Patel','Volkov')
     ORDER BY s.last_name;" \
    >> "$RESULT_FILE" 2>/dev/null || echo "Database query failed" >> "$RESULT_FILE"

echo "" >> "$RESULT_FILE"
echo "--- All Attendance on 2024-11-04 ---" >> "$RESULT_FILE"
mysql -u opensis_user -p'opensis_password_123' opensis -e \
    "SELECT a.attendance_id, s.first_name, s.last_name, a.attendance_date, a.status
     FROM attendance a
     INNER JOIN students s ON a.student_id = s.student_id
     WHERE a.attendance_date = '2024-11-04'
     ORDER BY s.last_name;" \
    >> "$RESULT_FILE" 2>/dev/null || true

echo "=== Export complete ==="
echo "Result saved to: $RESULT_FILE"
