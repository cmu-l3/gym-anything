#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Basic Presentation Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents/Presentations

# Launch LibreOffice Impress with a new presentation
echo "Launching LibreOffice Impress..."
su - ga -c "DISPLAY=:1 libreoffice --impress /home/ga/Documents/Presentations/basic_presentation.odp > /tmp/impress_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/impress_task.log
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Impress" 90; then
    echo "ERROR: LibreOffice Impress window did not appear"
fi

# Click on center to select desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Impress window
echo "Focusing Impress window..."
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    if focus_window "$wid"; then
        # Maximize window
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

echo "=== Basic Presentation Task Setup Complete ==="
echo "📝 Instructions:"
echo "  Create a presentation with 5 slides about 'Artificial Intelligence'"
echo "  Each slide should have:"
echo "    - A descriptive title"
echo "    - 2-3 bullet points with relevant content"
echo ""
echo "  Suggested topics:"
echo "    1. What is AI?"
echo "    2. Types of AI"
echo "    3. Applications of AI"
echo "    4. Benefits of AI"
echo "    5. Future of AI"
