#!/bin/bash
set -e
echo "=== Setting up assign_sprint_iteration task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running ReqView
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Set up a fresh copy of the example project
PROJECT_PATH=$(setup_task_project "sprint_planning")
echo "Task project path: $PROJECT_PATH"

# -----------------------------------------------------------------------------
# DATA PREPARATION:
# 1. Add 'Iteration' custom attribute to project.json
# 2. Randomize Priorities in SRS.json so the task is dynamic
# -----------------------------------------------------------------------------

python3 << PYEOF
import json
import random
import os

project_path = "$PROJECT_PATH"
project_json_path = os.path.join(project_path, "project.json")
srs_json_path = os.path.join(project_path, "documents", "SRS.json")

# 1. Add Iteration Attribute to project.json
try:
    with open(project_json_path, 'r') as f:
        proj = json.load(f)

    # Check if attributes list exists
    if 'attributes' not in proj:
        proj['attributes'] = []
    
    # Handle attributes as list or dict (ReqView format varies)
    attrs = proj['attributes']
    attr_exists = False
    
    # Define our new attribute
    new_attr = {
        "id": "iteration",
        "name": "Iteration",
        "type": "string",
        "width": 100
    }

    if isinstance(attrs, list):
        for a in attrs:
            if a.get('id') == 'iteration' or a.get('name') == 'Iteration':
                attr_exists = True
        if not attr_exists:
            attrs.append(new_attr)
    elif isinstance(attrs, dict):
        if 'iteration' not in attrs:
            attrs['iteration'] = new_attr

    with open(project_json_path, 'w') as f:
        json.dump(proj, f, indent=2)
    print("Added 'Iteration' attribute to project configuration.")

except Exception as e:
    print(f"Error modifying project.json: {e}")


# 2. Randomize Priorities and Clear Iterations in SRS.json
try:
    with open(srs_json_path, 'r') as f:
        srs = json.load(f)

    priorities = ['High', 'Medium', 'Low']
    
    def process_items(items):
        count = 0
        for item in items:
            # Only set priority for actual requirements (items with text/heading)
            if 'text' in item or 'heading' in item:
                # Randomly assign priority
                # ReqView stores Priority as 'H', 'M', 'L' usually, but custom templates might vary.
                # The Example Project usually uses an enumeration where keys are H, M, L.
                # Let's use the keys 'High', 'Medium', 'Low' if the attribute definition supports it,
                # or typically 'H', 'M', 'L'.
                # To be safe for the default template, we use 'High', 'Medium', 'Low' as values if it's text,
                # or keys if it's enum. 
                # For this setup, we'll assume the standard template uses string/enum values.
                # We will set the 'priority' field.
                
                # Note: In standard ReqView example, Priority is an enum with keys 'High', 'Medium', 'Low'.
                choice = random.choice(priorities)
                item['priority'] = choice
                
                # Clear iteration if it exists
                if 'iteration' in item:
                    del item['iteration']
                
                count += 1
            
            if 'children' in item:
                count += process_items(item['children'])
        return count

    modified_count = process_items(srs.get('data', []))
    
    with open(srs_json_path, 'w') as f:
        json.dump(srs, f, indent=2)
    print(f"Randomized priorities for {modified_count} requirements in SRS.")

except Exception as e:
    print(f"Error modifying SRS.json: {e}")

PYEOF

# -----------------------------------------------------------------------------
# LAUNCH APPLICATION
# -----------------------------------------------------------------------------

# Launch ReqView with the project
launch_reqview_with_project "$PROJECT_PATH"

# Wait for UI to stabilize
sleep 5

# Dismiss dialogs
dismiss_dialogs

# Maximize window
maximize_window

# Open the SRS document explicitly
open_srs_document

# Take initial screenshot
take_screenshot /tmp/task_initial.png

# Validate screenshot
if [ -f /tmp/task_initial.png ]; then
    echo "Initial state captured."
else
    echo "WARNING: Failed to capture initial state."
fi

echo "=== Setup complete ==="