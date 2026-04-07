#!/bin/bash
set -e
echo "=== Setting up perform_earned_value_analysis task ==="

# 1. Clean up previous run artifacts
rm -f /home/ga/Projects/project_status_update.xml
rm -f /home/ga/Projects/earned_value_report.pdf
rm -f /tmp/task_result.json
rm -f /tmp/task_start_time.txt

# 2. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 3. Ensure sample project exists in the working directory
mkdir -p /home/ga/Projects
if [ -f "/workspace/assets/sample_project.xml" ]; then
    cp /workspace/assets/sample_project.xml /home/ga/Projects/sample_project.xml
elif [ -f "/home/ga/Projects/samples/sample_project.xml" ]; then
    cp /home/ga/Projects/samples/sample_project.xml /home/ga/Projects/sample_project.xml
else
    # Fallback creation if missing (should be provided by env, but safe to have)
    echo "Warning: Sample project not found, using placeholder."
    # (In a real scenario, we would generate it here via python script if missing)
    # Assuming environment guarantees it per spec
fi
chown ga:ga /home/ga/Projects/sample_project.xml

# 4. Launch ProjectLibre
# We launch it *without* loading the file immediately, or *with* it depending on task flow.
# Description says "Open the project...", implying agent does it, OR we can preload it.
# To make it smoother, we'll preload it so the agent starts in the right context.
echo "Launching ProjectLibre with sample project..."
su - ga -c "DISPLAY=:1 setsid projectlibre /home/ga/Projects/sample_project.xml > /tmp/projectlibre.log 2>&1 &"

# 5. Wait for window to appear
echo "Waiting for ProjectLibre..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "projectlibre"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# 6. Maximize and focus
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ProjectLibre" 2>/dev/null || true

# 7. Dismiss any "Tips of the Day" or dialogs
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# 8. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="