#!/bin/bash
echo "=== Setting up export_to_csv task ==="

source /workspace/scripts/task_utils.sh

# Kill any running ReqView
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Ensure Documents directory exists and any old export is removed
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/srs_export.csv 2>/dev/null || true
chown ga:ga /home/ga/Documents

# Set up a fresh copy of the example project for this task
PROJECT_PATH=$(setup_task_project "export_csv")
echo "Task project path: $PROJECT_PATH"

# Add a predefined CSV export for the SRS document to the project configuration.
# This makes "SRS document to CSV" appear in the File > Export submenu.
PROJECT_JSON="$PROJECT_PATH/project.json"
if [ -f "$PROJECT_JSON" ]; then
    python3 << PYEOF
import json, sys
path = "$PROJECT_JSON"
try:
    with open(path) as f:
        proj = json.load(f)
except Exception as e:
    print(f"ERROR reading project.json: {e}", file=sys.stderr)
    sys.exit(0)

csv_export = {
    "input": ["SRS"],
    "name": "SRS document to CSV",
    "text": "Export SW requirements from the SRS document to CSV",
    "type": "csv"
}
# Add only if not already present
existing_names = [e.get("name","") for e in proj.get("exports", [])]
if "SRS document to CSV" not in existing_names:
    if "exports" not in proj:
        proj["exports"] = []
    proj["exports"].append(csv_export)
    with open(path, "w") as f:
        json.dump(proj, f, indent=2)
    print("Added 'SRS document to CSV' export to project.json")
else:
    print("CSV export already present in project.json")
PYEOF
else
    echo "WARNING: project.json not found at $PROJECT_JSON"
fi

# Launch ReqView with the project
launch_reqview_with_project "$PROJECT_PATH"

sleep 3

# Dismiss any dialogs
dismiss_dialogs

# Maximize window
maximize_window

# Open the SRS document in the project tree so it is visible to the agent
open_srs_document

take_screenshot /tmp/reqview_task_export_csv_start.png
echo "=== export_to_csv task setup complete ==="
