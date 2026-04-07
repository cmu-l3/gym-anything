#!/bin/bash
set -e

echo "=== Exporting Delivery Routing Engine Result ==="

WORKSPACE_DIR="/home/ga/workspace/routing_system"

# Focus VS Code and save file
DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool key ctrl+s" 2>/dev/null || true
sleep 1

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Test the agent's code
rm -f "$WORKSPACE_DIR/success.flag"
cd "$WORKSPACE_DIR"
su - ga -c "cd $WORKSPACE_DIR && python3 app.py" || true

RUN_SUCCESS="false"
if [ -f "$WORKSPACE_DIR/success.flag" ]; then
    RUN_SUCCESS="true"
fi

# Package results for the verifier
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 << PYEXPORT
import json, os

workspace = "$WORKSPACE_DIR"
engine_path = os.path.join(workspace, "routing_engine.py")

engine_code = ""
if os.path.exists(engine_path):
    with open(engine_path, "r", encoding="utf-8") as f:
        engine_code = f.read()

result = {
    "engine_code": engine_code,
    "run_success": "$RUN_SUCCESS",
    "screenshot_exists": os.path.exists("/tmp/task_final.png")
}

with open("$TEMP_JSON", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)
PYEXPORT

cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="