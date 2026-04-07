#!/bin/bash
echo "=== Setting up trace_reqs_by_content task ==="

source /workspace/scripts/task_utils.sh

# Kill any running ReqView
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Set up a fresh copy of the example project
PROJECT_PATH=$(setup_task_project "trace_content")
echo "Task project path: $PROJECT_PATH"

# Programmatically inject the specific "Orphan" requirements and Needs
# We use Python to manipulate the JSON files safely
python3 << PYEOF
import json
import os
import sys

project_path = "$PROJECT_PATH"
srs_path = os.path.join(project_path, "documents", "SRS.json")
needs_path = os.path.join(project_path, "documents", "NEEDS.json")

# 1. Inject Stakeholder Needs (Targets)
try:
    with open(needs_path, 'r') as f:
        needs_doc = json.load(f)
    
    # Create new Needs items
    new_needs = [
        {
            "id": "801",
            "text": "The system shall ensure user data remains private and secure against unauthorized access.",
            "heading": "Data Privacy",
            "status": "Approved"
        },
        {
            "id": "802",
            "text": "The system shall respond quickly to user inputs to maintain workflow efficiency.",
            "heading": "Performance",
            "status": "Approved"
        },
        {
            "id": "803",
            "text": "The system shall be usable by individuals with visual impairments.",
            "heading": "Inclusivity",
            "status": "Approved"
        }
    ]
    
    # Append to the end of the data array
    if "data" not in needs_doc:
        needs_doc["data"] = []
    
    # Add a section heading first to keep it organized
    needs_doc["data"].append({
        "id": "800",
        "heading": "New Stakeholder Needs (Unsatisfied)",
        "children": new_needs
    })
    
    with open(needs_path, 'w') as f:
        json.dump(needs_doc, f, indent=2)
    print("Injected 3 Stakeholder Needs")

except Exception as e:
    print(f"Error injecting NEEDS: {e}")
    sys.exit(1)

# 2. Inject System Requirements (Sources - Orphans)
try:
    with open(srs_path, 'r') as f:
        srs_doc = json.load(f)
        
    new_reqs = [
        {
            "id": "901",
            "text": "All customer data at rest shall be encrypted using AES-256 standard.",
            "status": "Draft",
            "links": [] # Explicitly no links
        },
        {
            "id": "902",
            "text": "The API average response latency shall not exceed 200ms under normal load.",
            "status": "Draft",
            "links": []
        },
        {
            "id": "903",
            "text": "User interface text shall maintain a contrast ratio of at least 4.5:1 (WCAG AA compliant).",
            "status": "Draft",
            "links": []
        }
    ]
    
    if "data" not in srs_doc:
        srs_doc["data"] = []
        
    srs_doc["data"].append({
        "id": "900",
        "heading": "Technical Implementation Specs",
        "children": new_reqs
    })
    
    with open(srs_path, 'w') as f:
        json.dump(srs_doc, f, indent=2)
    print("Injected 3 Orphan SRS Requirements")

except Exception as e:
    print(f"Error injecting SRS: {e}")
    sys.exit(1)

PYEOF

# Record start time
date +%s > /tmp/task_start_time.txt

# Launch ReqView
launch_reqview_with_project "$PROJECT_PATH"

sleep 5
dismiss_dialogs
maximize_window

# Open documents to make them visible to the agent
# Note: We open NEEDS first, then SRS, so SRS is the active tab (usually)
# Use xdotool to click the project tree items if possible, or just rely on the agent.
# Since the tree structure is standard, we can try to open them.
# "NEEDS" is typically above "SRS".
echo "Opening documents..."
# Approximate coordinates for project tree items (Top-left area)
# Needs typically 2nd or 3rd item.
# SRS typically 3rd or 4th.
# We'll just let the agent open them as part of the task "Open the SRS and NEEDS documents"
# but we can try to open at least one to be helpful.
open_srs_document

take_screenshot /tmp/task_initial.png
echo "=== Setup complete ==="