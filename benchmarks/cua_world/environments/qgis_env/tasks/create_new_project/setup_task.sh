#!/bin/bash
echo "=== Setting up create_new_project task ==="

source /workspace/scripts/task_utils.sh

# Ensure the project directory exists and is empty of any previous project
PROJECT_DIR="/home/ga/GIS_Data/projects"
mkdir -p "$PROJECT_DIR"

# Remove any existing project file with the expected name
rm -f "$PROJECT_DIR/my_first_project.qgs" 2>/dev/null || true
rm -f "$PROJECT_DIR/my_first_project.qgz" 2>/dev/null || true

# Record initial state
echo "0" > /tmp/initial_project_count
ls -1 "$PROJECT_DIR"/*.qgs 2>/dev/null | wc -l > /tmp/initial_project_count || echo "0" > /tmp/initial_project_count

echo "Initial project count: $(cat /tmp/initial_project_count)"

# Kill any running QGIS instances
kill_qgis ga 2>/dev/null || true
sleep 1

# Launch QGIS
echo "Launching QGIS..."
su - ga -c "DISPLAY=:1 qgis > /tmp/qgis_task.log 2>&1 &"

# Wait for QGIS window to appear
sleep 5
wait_for_window "QGIS" 30

# Give it a moment to fully initialize
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Task: Create a new QGIS project and save it as 'my_first_project.qgs' in $PROJECT_DIR"
