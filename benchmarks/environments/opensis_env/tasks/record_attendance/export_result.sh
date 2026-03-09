#!/bin/bash
set -euo pipefail

echo "=== Exporting record_attendance task result ==="

export DISPLAY=${DISPLAY:-:1}
RESULT_FILE="/tmp/task_result.txt"

WINDOW_TITLE=$(xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
echo "Window Title: $WINDOW_TITLE" > "$RESULT_FILE"

scrot /tmp/task_screenshot.png 2>/dev/null || true

echo "" >> "$RESULT_FILE"
echo "--- Attendance Records ---" >> "$RESULT_FILE"

mysql -u opensis_user -p'opensis_password_123' opensis -e \
    "SELECT a.attendance_id, s.first_name, s.last_name, a.attendance_date, a.status
     FROM attendance a
     JOIN students s ON a.student_id = s.student_id
     ORDER BY a.attendance_id DESC LIMIT 10;" \
    >> "$RESULT_FILE" 2>/dev/null || echo "Database query failed" >> "$RESULT_FILE"

echo "" >> "$RESULT_FILE"
echo "--- Today's Attendance ---" >> "$RESULT_FILE"
mysql -u opensis_user -p'opensis_password_123' opensis -e \
    "SELECT * FROM attendance WHERE attendance_date = CURDATE();" \
    >> "$RESULT_FILE" 2>/dev/null || true

echo "=== Export complete ==="
