#!/bin/bash
set -e
echo "=== Setting up create_inline_link_to_requirement task ==="

source /workspace/scripts/task_utils.sh

# 1. Kill any running ReqView instances
pkill -f "reqview" 2>/dev/null || true
sleep 2

# 2. Setup Project Directory
# We use a unique project name to ensure a clean state
PROJECT_NAME="create_inline_link_project"
PROJECT_DIR=$(setup_task_project "$PROJECT_NAME")
echo "Task project path: $PROJECT_DIR"

# 3. Inject Data: Modify SRS-001 description and ensure NEED-001 exists
# We use Python to safely manipulate the JSON structure
python3 << PYEOF
import json
import os
import sys

project_dir = "$PROJECT_DIR"
docs_dir = os.path.join(project_dir, "documents")

srs_path = os.path.join(docs_dir, "SRS.json")
needs_path = os.path.join(docs_dir, "NEEDS.json")

# Ensure documents exist
if not os.path.exists(srs_path) or not os.path.exists(needs_path):
    print(f"ERROR: Document files missing in {docs_dir}", file=sys.stderr)
    sys.exit(1)

# --- Modify SRS-001 ---
try:
    with open(srs_path, "r") as f:
        srs_data = json.load(f)

    # Recursive function to find and update SRS-001
    def update_srs_001(nodes):
        for node in nodes:
            if node.get("id") == "SRS-001":
                # Set the text specifically for this task
                node["text"] = "This system behavior is derived directly from NEED-001 to ensure compliance."
                # Remove 'xhtml' to ensure it starts as plain text without links
                if "xhtml" in node:
                    del node["xhtml"]
                return True
            if "children" in node:
                if update_srs_001(node["children"]):
                    return True
        return False

    if update_srs_001(srs_data.get("data", [])):
        with open(srs_path, "w") as f:
            json.dump(srs_data, f, indent=2)
        print("Successfully updated SRS-001 description.")
    else:
        # If SRS-001 doesn't exist (e.g. project structure changed), inject it
        print("SRS-001 not found, injecting it...")
        # (Simplified injection logic - appending to root)
        if "data" not in srs_data:
            srs_data["data"] = []
        import uuid
        new_req = {
            "id": "SRS-001",
            "guid": str(uuid.uuid4()),
            "heading": "System Behavior",
            "text": "This system behavior is derived directly from NEED-001 to ensure compliance.",
            "type": "functional"
        }
        srs_data["data"].insert(0, new_req)
        with open(srs_path, "w") as f:
            json.dump(srs_data, f, indent=2)

except Exception as e:
    print(f"ERROR updating SRS.json: {e}", file=sys.stderr)
    sys.exit(1)

# --- Verify NEED-001 ---
try:
    with open(needs_path, "r") as f:
        needs_data = json.load(f)

    def find_need_001(nodes):
        for node in nodes:
            if node.get("id") == "NEED-001":
                return True
            if "children" in node:
                if find_need_001(node["children"]):
                    return True
        return False

    if find_need_001(needs_data.get("data", [])):
        print("NEED-001 confirmed in NEEDS.json")
    else:
        print("WARNING: NEED-001 not found in NEEDS.json. Task might be impossible.")

except Exception as e:
    print(f"ERROR checking NEEDS.json: {e}", file=sys.stderr)
    # Don't exit, try to proceed

PYEOF

# 4. Launch ReqView with the project
launch_reqview_with_project "$PROJECT_DIR"

# 5. Prepare UI
# Wait for load, dismiss dialogs, maximize
sleep 5
dismiss_dialogs
maximize_window

# 6. Open the SRS document so the agent sees the target requirement immediately
open_srs_document

# 7. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
# Record modification time of SRS.json to detect saves
stat -c %Y "$PROJECT_DIR/documents/SRS.json" > /tmp/initial_srs_mtime.txt

# 8. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="