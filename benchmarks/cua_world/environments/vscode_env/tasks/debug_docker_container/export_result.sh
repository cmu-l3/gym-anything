#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Debug Docker Container Result ==="

WORKSPACE_DIR="/home/ga/workspace/flask_docker_project"

# Save any open files in VSCode
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
} || {
    echo "⚠️ Failed to save files in VSCode; continuing"
}

sleep 2

# Export container status
echo "Exporting Docker container status..."
docker ps -a --filter "name=flask_debug_app" --format "{{.Names}}|{{.Status}}|{{.Ports}}" > /tmp/docker_status.txt 2>&1 || echo "No container" > /tmp/docker_status.txt

# Export container port mappings
docker port flask_debug_app > /tmp/docker_ports.txt 2>&1 || echo "" > /tmp/docker_ports.txt

# Check if debugpy is installed in container
docker exec flask_debug_app pip show debugpy > /tmp/debugpy_status.txt 2>&1 || echo "not installed" > /tmp/debugpy_status.txt

# Export installed packages in container
docker exec flask_debug_app pip list > /tmp/pip_list.txt 2>&1 || echo "" > /tmp/pip_list.txt

# Copy main.py to tmp for verification
docker cp flask_debug_app:/app/main.py /tmp/main_py_container.py 2>/dev/null || cp "$WORKSPACE_DIR/app/main.py" /tmp/main_py_container.py 2>/dev/null || echo "# File not found" > /tmp/main_py_container.py

# Copy launch.json if it exists
if [ -f "$WORKSPACE_DIR/.vscode/launch.json" ]; then
    cp "$WORKSPACE_DIR/.vscode/launch.json" /tmp/launch_json_export.json
else
    echo "{}" > /tmp/launch_json_export.json
fi

# Copy docker-compose.yml for verification
cp "$WORKSPACE_DIR/docker-compose.yml" /tmp/docker_compose_export.yml 2>/dev/null || echo "" > /tmp/docker_compose_export.yml

# Test Flask endpoint responsiveness
curl -s -X POST http://localhost:5000/api/calculate \
  -H "Content-Type: application/json" \
  -d '{"price": 100, "discount_rate": 20}' > /tmp/flask_response.json 2>&1 || echo '{"error": "not responding"}' > /tmp/flask_response.json

echo "✅ Export complete"
echo "Container status: $(cat /tmp/docker_status.txt)"
echo "Debug port status: $(cat /tmp/docker_ports.txt | grep 5678 || echo 'Not exposed')"
echo "Debugpy status: $(cat /tmp/debugpy_status.txt | head -n 1)"