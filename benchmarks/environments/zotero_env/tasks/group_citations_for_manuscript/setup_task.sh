#!/bin/bash
echo "=== Setting up group_citations_for_manuscript task ==="

# 1. Stop Zotero to safely modify database
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# 2. Seed library with papers (Classic + ML sets)
# This provides the target papers AND the distractors (Turing 1950, Shannon 1949)
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode all > /tmp/seed_log.txt 2>&1
if [ $? -ne 0 ]; then
    echo "ERROR: Seeding failed"
    cat /tmp/seed_log.txt
    exit 1
fi

# 3. Create a target citations list file for the agent to reference (optional but helpful context)
cat > /home/ga/Documents/target_citations.txt << EOF
Target References for Manuscript 2024:

1. Turing, A. M. (1936). On Computable Numbers, with an Application to the Entscheidungsproblem.
2. Shannon, C. E. (1948). A Mathematical Theory of Communication.
3. Vaswani, A., et al. (2017). Attention Is All You Need.
4. Silver, D., et al. (2016). Mastering the Game of Go with Deep Neural Networks and Tree Search.
EOF
chown ga:ga /home/ga/Documents/target_citations.txt

# 4. Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# 5. Restart Zotero
echo "Restarting Zotero..."
# Use setsid to detach from shell, avoiding hang
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote > /dev/null 2>&1 &"

# 6. Wait for window and maximize
echo "Waiting for Zotero window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "zotero"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Ensure maximized and focused
sleep 2
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# 7. Initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="