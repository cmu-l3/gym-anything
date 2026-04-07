#!/bin/bash
echo "=== Setting up bcf_issue_authoring task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Ensure directories exist
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# 2. Remove any existing output file to prevent false positives
rm -f /home/ga/BIMProjects/coordination_issues.bcfzip 2>/dev/null || true

# 3. Verify the IFC model exists
if [ ! -f /home/ga/IFCModels/fzk_haus.ifc ]; then
    echo "WARNING: fzk_haus.ifc not found! Downloading..."
    wget -q "https://www.ifcwiki.org/images/e/e3/AC20-FZK-Haus.ifc" -O /home/ga/IFCModels/fzk_haus.ifc
fi
chown ga:ga /home/ga/IFCModels/fzk_haus.ifc

# 4. Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_timestamp
echo "Task start time: $(cat /tmp/task_start_timestamp)"

# 5. Kill any existing Blender instances
kill_blender

# 6. Launch Blender (empty session - agent must load the IFC)
echo "Launching Blender..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender > /tmp/blender_task.log 2>&1 &"

# 7. Wait for Blender window
WAIT_COUNT=0
while [ $WAIT_COUNT -lt 15 ]; do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -i "blender" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        echo "Blender window detected: $WID"
        break
    fi
    sleep 2
    WAIT_COUNT=$((WAIT_COUNT + 1))
done
sleep 3

# 8. Focus, maximize, screenshot
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "Blender is running with an empty session."
echo "Agent must load /home/ga/IFCModels/fzk_haus.ifc and create a BCF issue."