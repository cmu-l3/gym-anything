#!/bin/bash
echo "=== Setting up export_selected_items_to_bibtex task ==="

# 1. Clean up previous artifacts
rm -f /home/ga/Documents/info_theory_foundations.bib
rm -f /tmp/task_result.json

# 2. Stop Zotero for database seeding
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 2

# 3. Seed library with classic papers (includes the targets) and ML papers
# Using 'all' mode to populate library with 18 items
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode all > /tmp/seed_output.txt 2>&1

# 4. Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 5. Start Zotero
echo "Starting Zotero..."
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote &"

# 6. Wait for Zotero window
echo "Waiting for Zotero window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "zotero"; then
        echo "Zotero window detected"
        break
    fi
    sleep 1
done

# 7. Maximize and focus
sleep 2
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# 8. Take initial screenshot
echo "Taking initial screenshot..."
sleep 1
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="