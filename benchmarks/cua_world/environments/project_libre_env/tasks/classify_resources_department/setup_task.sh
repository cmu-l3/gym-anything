#!/bin/bash
set -e
echo "=== Setting up classify_resources_department task ==="

# 1. Environment Preparation
# Ensure the Projects directory exists and has correct permissions
mkdir -p /home/ga/Projects
chown -R ga:ga /home/ga/Projects

# 2. Data Staging
# Copy the sample project to a working file
SOURCE_XML="/workspace/assets/sample_project.xml"
# Fallback if assets mount isn't perfect, use the one generated in env setup or create it
if [ ! -f "$SOURCE_XML" ]; then
    SOURCE_XML="/home/ga/Projects/samples/sample_project.xml"
fi

WORK_FILE="/home/ga/Projects/sample_project.xml"

if [ -f "$SOURCE_XML" ]; then
    cp "$SOURCE_XML" "$WORK_FILE"
    echo "Loaded sample project to $WORK_FILE"
else
    echo "ERROR: Sample project source not found."
    exit 1
fi

# Ensure clean state for output
rm -f /home/ga/Projects/categorized_resources.xml

# Set permissions
chown ga:ga "$WORK_FILE"

# 3. Time Synchronization (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 4. Launch Application
# Kill any existing instances
pkill -f "projectlibre" 2>/dev/null || true
sleep 1

echo "Launching ProjectLibre..."
# Launching with the file argument to open it immediately
su - ga -c "DISPLAY=:1 setsid projectlibre '$WORK_FILE' > /tmp/projectlibre.log 2>&1 &"

# 5. Wait for Window
echo "Waiting for ProjectLibre window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "projectlibre" > /dev/null; then
        echo "Window detected."
        break
    fi
    sleep 1
done

# Short wait for UI components to render (Java Swing can be slow)
sleep 5

# 6. Window Management
# Maximize window
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Focus window
DISPLAY=:1 wmctrl -a "ProjectLibre" 2>/dev/null || true

# Dismiss common startup dialogs (Tip of the Day, etc) if any
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 7. Initial Evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="