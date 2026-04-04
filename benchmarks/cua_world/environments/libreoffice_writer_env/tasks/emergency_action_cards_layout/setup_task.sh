#!/bin/bash
set -euo pipefail

echo "=== Setting up Emergency Action Cards Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create the content file
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/card_content.txt << 'EOF'
[RED CARD]
CODE RED
IMMEDIATE EVACUATION
1. Stop all machinery
2. Proceed to North Exit
3. Muster at Point A

[YELLOW CARD]
CODE YELLOW
SHELTER IN PLACE
1. Close all windows/doors
2. Move to interior hallway
3. Await instructions

[BLUE CARD]
CODE BLUE
MEDICAL EMERGENCY
1. Clear corridor
2. Call ext. 911
3. Send guide to entrance

[GREEN CARD]
ALL CLEAR
RETURN TO WORK
1. Report to supervisor
2. Reset equipment
3. Resume operations
EOF

chown ga:ga /home/ga/Documents/card_content.txt
chmod 666 /home/ga/Documents/card_content.txt

# Start LibreOffice Writer (empty)
echo "Starting LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore > /dev/null 2>&1 &"

# Wait for window
wait_for_window "LibreOffice Writer" 30 || echo "Warning: Writer window not detected yet"

# Maximize and focus
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="