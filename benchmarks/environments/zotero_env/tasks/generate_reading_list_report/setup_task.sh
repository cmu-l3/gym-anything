#!/bin/bash
# Setup for generate_reading_list_report
# Seeds library with ML collection and prepares environment

echo "=== Setting up generate_reading_list_report task ==="
source /workspace/scripts/task_utils.sh

DB="/home/ga/Zotero/zotero.sqlite"
OUTPUT_FILE="/home/ga/Documents/reading_list.html"

# 1. Clean up previous artifacts
rm -f "$OUTPUT_FILE"
# Also clean up potential variations
rm -f /home/ga/Documents/Zotero_Report.html
rm -f /home/ga/reading_list.html

# 2. Stop Zotero to seed DB
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 2

# 3. Seed library with 'Machine Learning Papers' collection
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode ml_with_collection > /tmp/seed_output.log 2>&1
if [ $? -ne 0 ]; then
    echo "ERROR: Seeding failed"
    cat /tmp/seed_output.log
    exit 1
fi

# 4. Record task start time
date +%s > /tmp/task_start_time.txt

# 5. Restart Zotero
echo "Restarting Zotero..."
# Use setsid to detach from shell, standard pattern for this env
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote &"

# 6. Wait for window and maximize
echo "Waiting for Zotero window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "zotero"; then
        echo "Window found"
        break
    fi
    sleep 1
done

sleep 3
# Activate and maximize
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="