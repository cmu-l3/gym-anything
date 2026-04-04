#!/bin/bash
echo "=== Setting up export_collection_csv task ==="

# 1. Clean up any previous run artifacts
rm -f /home/ga/Documents/ml_papers.csv
rm -f /tmp/task_result.json

# 2. Stop Zotero to safely modify database
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# 3. Seed library with ML collection
# Using mode 'ml_with_collection' which creates "Machine Learning Papers" collection
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode ml_with_collection > /tmp/seed.log 2>&1
if [ $? -ne 0 ]; then
    echo "Error seeding library:"
    cat /tmp/seed.log
    # Fallback: try generic seeding if specific mode fails
    python3 /workspace/scripts/seed_library.py --mode ml > /dev/null 2>&1
fi

# 4. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 5. Start Zotero
echo "Starting Zotero..."
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote > /home/ga/zotero.log 2>&1 &"

# 6. Wait for Zotero window
echo "Waiting for Zotero window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Zotero"; then
        echo "Zotero window detected"
        break
    fi
    sleep 1
done

# 7. Maximize and focus
sleep 2
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# 8. Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="