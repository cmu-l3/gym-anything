#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Add Animations Task ==="

# Ensure directories exist
mkdir -p /home/ga/Documents/Presentations
chown -R ga:ga /home/ga/Documents

# Kill any leftover LibreOffice processes and clean recovery files
kill_libreoffice
rm -rf /home/ga/.config/libreoffice/4/user/backup/ 2>/dev/null || true
rm -rf /tmp/lu*/ 2>/dev/null || true
rm -f /tmp/.~lock.* 2>/dev/null || true

# Copy the real IRENA renewable energy presentation as starting data
cp /workspace/assets/renewable_energy_report.odp /home/ga/Documents/Presentations/animation_test.odp
chown ga:ga /home/ga/Documents/Presentations/animation_test.odp

echo "Copied real data: IRENA Renewable Energy Report (5 slides)"

# Launch LibreOffice Impress with the presentation
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 setsid libreoffice --impress /home/ga/Documents/Presentations/animation_test.odp > /tmp/impress_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 30; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/impress_task.log 2>/dev/null || true
fi

# Wait for window to appear
if ! wait_for_window "Impress\|impress\|animation_test\|\.odp" 90; then
    echo "WARNING: LibreOffice Impress window did not appear in time"
fi
sleep 3

# Dismiss any Document Recovery dialog if it appears
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Recovery"; then
    echo "Dismissing Document Recovery dialog..."
    su - ga -c "DISPLAY=:1 xdotool key Escape" || true
    sleep 2
fi

# Focus and maximize the Impress window
focus_window "Impress" || focus_window "animation_test" || focus_window "LibreOffice" || true
sleep 1
maximize_window "Impress" || maximize_window "animation_test" || maximize_window "LibreOffice" || true
sleep 1

echo "=== Add Animations Task Setup Complete ==="
echo "Task: Add slide transitions and object animations to the IRENA report"
echo "  1. Add slide transitions to all 5 slides"
echo "  2. Add object animations to text elements"
echo "  File: /home/ga/Documents/Presentations/animation_test.odp"
