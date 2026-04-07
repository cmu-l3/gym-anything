#!/bin/bash
set -e

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Basic Presentation Task ==="

# Ensure directories exist
mkdir -p /home/ga/Documents/Presentations
chown -R ga:ga /home/ga/Documents

# Kill any leftover LibreOffice processes and clean recovery files
kill_libreoffice
rm -rf /home/ga/.config/libreoffice/4/user/backup/ 2>/dev/null || true
rm -rf /tmp/lu*/ 2>/dev/null || true
rm -f /tmp/.~lock.* 2>/dev/null || true

# Launch LibreOffice Impress with a new blank presentation (no file argument)
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 setsid libreoffice --impress > /tmp/impress_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 30; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/impress_task.log 2>/dev/null || true
fi

# Wait for window to appear
if ! wait_for_window "Impress\|impress\|\.odp\|Untitled\|LibreOffice" 90; then
    echo "WARNING: LibreOffice Impress window did not appear in time"
fi
sleep 3

# Dismiss any dialogs (Document Recovery, Template Selector, What's New)
for attempt in 1 2 3; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Recovery\|Template\|What"; then
        echo "Dismissing dialog (attempt $attempt)..."
        su - ga -c "DISPLAY=:1 xdotool key Escape" || true
        sleep 2
    else
        break
    fi
done

# Close the "What's New" info bar if present (click the X at top)
su - ga -c "DISPLAY=:1 xdotool key Escape" || true
sleep 1

# Focus and maximize the Impress window
focus_window "Impress" || focus_window "LibreOffice" || true
sleep 1
maximize_window "Impress" || maximize_window "LibreOffice" || true
sleep 1

echo "=== Basic Presentation Task Setup Complete ==="
echo "Task: Create a 5-slide presentation about 'Artificial Intelligence'"
echo "  Each slide should have a title and 2-3 bullet points."
echo "  Save to /home/ga/Documents/Presentations/basic_presentation.odp"
