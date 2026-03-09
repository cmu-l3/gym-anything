#!/bin/bash
# set -euo pipefail

echo "=== Setting up Conditional Format task ==="

source /workspace/scripts/task_utils.sh

cat > /home/ga/Documents/student_scores.csv << 'EOF'
Student,Score
Alice,85
Bob,58
Charlie,92
David,45
Eve,78
Frank,95
EOF

chown ga:ga /home/ga/Documents/student_scores.csv

su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/student_scores.csv > /tmp/libreoffice_format.log 2>&1 &"
sleep 5

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_ga.log
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
fi


# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Calc window
echo "Focusing Calc window..."
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    if focus_window "$wid"; then
        # Maximize window
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

echo "=== Conditional Format task setup completed ==="
echo "📋 Task: Apply conditional formatting to Score column"
echo "💡 Green for >= 80, Red for < 60"
