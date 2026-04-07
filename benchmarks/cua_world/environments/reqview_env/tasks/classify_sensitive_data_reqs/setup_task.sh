#!/bin/bash
set -e
echo "=== Setting up classify_sensitive_data_reqs task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Create a fresh project directory
PROJECT_DIR=$(setup_task_project "classify_sensitive_project")
SRS_FILE="$PROJECT_DIR/documents/SRS.json"
PROJECT_FILE="$PROJECT_DIR/project.json"
GROUND_TRUTH_DIR="/var/lib/reqview"
mkdir -p "$GROUND_TRUTH_DIR"

echo "Project location: $PROJECT_DIR"

# Python script to:
# 1. Inject DataClassification attribute into project.json
# 2. Inject IPv4 addresses into SRS.json requirements
# 3. Save ground truth list
python3 << PYEOF
import json
import random
import sys
import os

project_path = "$PROJECT_FILE"
srs_path = "$SRS_FILE"
ground_truth_path = "$GROUND_TRUTH_DIR/ground_truth.json"

# --- Step 1: Add Custom Attribute ---
try:
    with open(project_path, 'r') as f:
        project_data = json.load(f)

    # Check if 'attributes' is a list or dict (ReqView varies)
    # We will assume list for the bundled example or convert if needed
    attrs = project_data.get('attributes', [])
    if isinstance(attrs, dict):
        # If it's a dict, we just add a new key
        new_attr = {
            "name": "DataClassification",
            "type": "enum",
            "values": ["Public", "Internal", "Confidential"],
            "default": "Public"
        }
        # Use a random ID for the attribute key if needed, or just append if list
        # For simplicity, we'll force it into the structure found.
        # But wait, ReqView example usually has a list or dict. 
        # Let's just append to list if it's a list.
        pass 
    
    # Construct the attribute definition
    classification_attr = {
        "name": "DataClassification",
        "type": "enum",
        "values": [
            {"key": "Public", "label": "Public"},
            {"key": "Internal", "label": "Internal"},
            {"key": "Confidential", "label": "Confidential"}
        ],
        "default": "Public"
    }

    # If attributes is a list, append.
    if isinstance(attrs, list):
        attrs.append(classification_attr)
    elif isinstance(attrs, dict):
        # Generate a unique key
        attrs["attr_dataclass"] = classification_attr
    
    project_data['attributes'] = attrs
    
    with open(project_path, 'w') as f:
        json.dump(project_data, f, indent=2)
    print(f"Added DataClassification attribute to {project_path}")

except Exception as e:
    print(f"Error modifying project.json: {e}")
    sys.exit(1)

# --- Step 2: Inject IP Addresses ---
target_ids = []

try:
    with open(srs_path, 'r') as f:
        srs_data = json.load(f)

    # Helper to find leaf nodes (requirements)
    def get_leaves(nodes):
        leaves = []
        for node in nodes:
            if 'children' in node and node['children']:
                leaves.extend(get_leaves(node['children']))
            else:
                # Only use valid requirements (have an ID)
                if 'id' in node:
                    leaves.append(node)
        return leaves

    all_reqs = get_leaves(srs_data.get('data', []))
    
    # Select 4-6 random requirements to inject
    num_targets = random.randint(4, 6)
    targets = random.sample(all_reqs, min(num_targets, len(all_reqs)))
    
    print(f"Injecting IPs into {len(targets)} requirements...")
    
    for req in targets:
        # Generate random IP
        ip = f"192.168.{random.randint(0,255)}.{random.randint(1,254)}"
        
        # Injection templates
        templates = [
            f" (Legacy server IP: {ip})",
            f" Connection endpoint: {ip}.",
            f" <p><strong>Note:</strong> Hardcoded reference to {ip} must be maintained.</p>",
            f" Default gateway: {ip}"
        ]
        
        injection = random.choice(templates)
        
        # Append to text or description
        if 'text' in req:
            # ReqView stores rich text HTML in 'text'
            if req['text'].endswith('</p>'):
                req['text'] = req['text'][:-4] + injection + "</p>"
            else:
                req['text'] += injection
        elif 'description' in req:
            req['description'] += injection
        
        target_ids.append(req['id'])
        print(f"  - Injected {ip} into {req['id']}")

    # Save modified SRS
    with open(srs_path, 'w') as f:
        json.dump(srs_data, f, indent=2)

    # --- Step 3: Save Ground Truth ---
    gt_data = {
        "target_ids": target_ids,
        "total_targets": len(target_ids)
    }
    
    with open(ground_truth_path, 'w') as f:
        json.dump(gt_data, f, indent=2)
    print(f"Saved ground truth to {ground_truth_path}")

except Exception as e:
    print(f"Error modifying SRS.json: {e}")
    sys.exit(1)

PYEOF

# Ensure permissions
chown -R ga:ga "$PROJECT_DIR"
chown ga:ga "$PROJECT_DIR/project.json" "$PROJECT_DIR/documents/SRS.json"

# Launch ReqView
echo "Launching ReqView..."
launch_reqview_with_project "$PROJECT_DIR"

sleep 5
dismiss_dialogs
maximize_window

# Ensure Attributes pane is visible (it usually is by default, but agent might need to toggle it)
# We won't force it, but we open the SRS document
open_srs_document

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="