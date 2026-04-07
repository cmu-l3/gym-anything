#!/bin/bash
set -e
echo "=== Setting up Resolve Suspect Link Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Kill any running ReqView
pkill -f "reqview" 2>/dev/null || true
sleep 2

# 2. Setup fresh project
PROJECT_PATH=$(setup_task_project "suspect_link")
echo "Project created at: $PROJECT_PATH"

# 3. Programmatically create a Suspect Link scenario
# We modify NEEDS.doc.json to update a requirement's text and timestamp.
# This causes the existing link in SRS.doc.json (which points to the old timestamp) to become suspect.

python3 << PYEOF
import json
import os
import sys
import datetime

project_dir = "$PROJECT_PATH"
documents_dir = os.path.join(project_dir, "documents")
needs_file = os.path.join(documents_dir, "NEEDS.json")
srs_file = os.path.join(documents_dir, "SRS.json")

print(f"Modifying project files in {documents_dir}...")

# Load SRS to find a valid link to NEEDS
try:
    with open(srs_file, "r") as f:
        srs_data = json.load(f)
except Exception as e:
    print(f"ERROR reading SRS.json: {e}")
    sys.exit(1)

# Find a requirement that has a link to NEEDS
target_link = None
srs_req_id = None
needs_req_id = None

# Helper to traverse hierarchy
def find_link(items):
    for req in items:
        links = req.get("links", [])
        for link in links:
            # Check if link points to NEEDS document
            # srcId format usually "NEEDS-123" or just "123" if docId is separate
            # In ReqView JSON, docId is often separate.
            doc_id = link.get("docId", "")
            if doc_id == "NEEDS" or link.get("srcId", "").startswith("NEEDS"):
                return req, link
        
        if "children" in req:
            res = find_link(req["children"])
            if res:
                return res
    return None

result = find_link(srs_data.get("children", []) or srs_data.get("data", []))

if not result:
    print("ERROR: Could not find any link to NEEDS in SRS document")
    sys.exit(1)

req, link = result
srs_req_id = req.get("id")
needs_req_id = link.get("srcId") # This might be the int ID or string ID
target_doc_id = link.get("docId", "NEEDS")

print(f"Selected pair: SRS-{srs_req_id} -> {target_doc_id}-{needs_req_id}")

# Load NEEDS to modify the source
try:
    with open(needs_file, "r") as f:
        needs_data = json.load(f)
except Exception as e:
    print(f"ERROR reading NEEDS.json: {e}")
    sys.exit(1)

# Find the NEEDS requirement
found_need = False

def update_need(items, target_id):
    for req in items:
        # ID match might need string comparison
        if str(req.get("id")) == str(target_id):
            return req
        if "children" in req:
            res = update_need(req["children"], target_id)
            if res:
                return res
    return None

need_req = update_need(needs_data.get("children", []) or needs_data.get("data", []), needs_req_id)

if not need_req:
    print(f"ERROR: Could not find definition for NEEDS-{needs_req_id}")
    sys.exit(1)

# MODIFY THE TEXT to trigger suspect flag
original_text = need_req.get("text", "")
# Strip HTML p tags for clean append if present, though simple append works too
need_req["text"] = original_text + " <span style=\"color:blue\">(Updated by Stakeholder)</span>"

# Update changedOn/lastModified timestamp to a newer date
# ReqView uses ISO format: "2023-10-27T10:00:00.000Z"
new_time = datetime.datetime.utcnow().isoformat() + "Z"
need_req["lastModified"] = new_time
need_req["changedOn"] = new_time # ReqView uses different fields in different versions, updating both to be safe

print(f"Modified NEEDS-{needs_req_id}: '{need_req['text']}' at {new_time}")

# Save modified NEEDS
with open(needs_file, "w") as f:
    json.dump(needs_data, f, indent=2)

print("Successfully modified NEEDS document to trigger suspect link.")

# Save IDs for verification
with open("/tmp/suspect_ids.txt", "w") as f:
    f.write(f"{srs_req_id},{needs_req_id},{target_doc_id}")
PYEOF

# 4. Launch ReqView
launch_reqview_with_project "$PROJECT_PATH"

# 5. Dismiss dialogs and maximize
dismiss_dialogs
maximize_window

# 6. Open SRS document
open_srs_document

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="