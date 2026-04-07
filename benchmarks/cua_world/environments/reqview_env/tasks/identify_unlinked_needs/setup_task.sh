#!/bin/bash
set -e
echo "=== Setting up identify_unlinked_needs task ==="

source /workspace/scripts/task_utils.sh

# Anti-gaming timestamp
date +%s > /tmp/task_start_time.txt

# 1. Setup Project
# We copy the example project to a task-specific directory
PROJECT_DIR=$(setup_task_project "gap_analysis")
echo "Project setup at: $PROJECT_DIR"

# 2. Prepare Ground Truth and Modify Data (Inject Gaps)
# The default example project might be fully linked. We need to ensuring there are specific unlinked needs.
# We will programmatically remove links from SRS to specific NEEDS to create gaps.

GROUND_TRUTH_DIR="/var/lib/reqview_ground_truth"
mkdir -p "$GROUND_TRUTH_DIR"

python3 << PY_SCRIPT
import json
import os
import sys

project_dir = "$PROJECT_DIR"
srs_path = os.path.join(project_dir, "documents", "SRS.json")
needs_path = os.path.join(project_dir, "documents", "NEEDS.json")
gt_path = os.path.join("$GROUND_TRUTH_DIR", "ground_truth.json")

def load_json(path):
    with open(path, 'r') as f:
        return json.load(f)

def save_json(path, data):
    with open(path, 'w') as f:
        json.dump(data, f, indent=2)

def get_all_ids(data_node, prefix):
    ids = set()
    # ReqView data items structure
    item_id = data_node.get('id')
    # If the item has a text or heading, it's likely a requirement/section
    if item_id:
        # Construct full ID usually formatted as PREFIX-ID (e.g. NEEDS-20)
        # But internally it's often just the integer ID.
        # We'll store the internal ID for matching.
        ids.add(str(item_id))
    
    for child in data_node.get('children', []):
        ids.update(get_all_ids(child, prefix))
    return ids

# Flatten structure to list of all items for easier link processing
def get_flat_items(data_nodes):
    items = []
    for node in data_nodes:
        items.append(node)
        items.extend(get_flat_items(node.get('children', [])))
    return items

try:
    print("Loading documents...")
    srs_data = load_json(srs_path)
    needs_data = load_json(needs_path)
    
    # 1. Create Gaps: Remove links in SRS that point to specific NEEDS
    # We want to ensure at least 3-4 needs are unlinked for the task to be interesting.
    # Let's target NEEDS items that are currently linked and unlink them.
    
    srs_items = get_flat_items(srs_data.get('data', []))
    
    # Track which NEEDS are linked
    linked_needs = set()
    
    # Identify links and remove some
    # In the example project, SRS items usually "satisfy" NEEDS items.
    # Link: { "srcId": "SRS-123", "destId": "NEEDS-456", "type": "satisfies" }
    # ReqView stores links in the source object in a 'links' array: [{ "reqId": "456", "docId": "NEEDS" }]
    
    modifications = 0
    
    # Let's forcefully unlink specific NEEDS by removing referencing links in SRS
    # We'll pick a few IDs dynamically if possible, or just nuke links from random SRS items
    
    # First, let's map NEEDS items
    needs_items = get_flat_items(needs_data.get('data', []))
    all_needs_ids = set(str(n['id']) for n in needs_items if 'id' in n)
    
    # Find links in SRS pointing to NEEDS
    for item in srs_items:
        if 'links' in item:
            new_links = []
            for link in item['links']:
                # Check if this link points to NEEDS
                # Note: docId might be the document ID (GUID) or alias ('NEEDS')
                # In the example project, aliases like 'NEEDS' are often used, or GUIDs.
                # We'll assume 'NEEDS' or check the document GUID if available.
                
                target_doc = link.get('docId', '')
                # To create gaps, we drop every 5th link to NEEDS, ensuring we have some unlinked ones
                # Or better, let's unlink specific ones to be deterministic if we knew the IDs.
                # Since we want a robust task, let's unlink based on a hash or counter to be deterministic but dynamic.
                
                # Check if it points to NEEDS doc (usually by ID or Alias)
                # We'll just check if the ID matches a known NEED ID to be sure
                target_id = str(link.get('reqId', ''))
                
                if target_id in all_needs_ids and (int(target_id) % 3 == 0):
                    # UNLINK THIS ONE! (Remove link)
                    print(f"Removing link from SRS-{item.get('id')} to NEEDS-{target_id}")
                    modifications += 1
                else:
                    new_links.append(link)
            
            item['links'] = new_links

    # Save modified SRS
    save_json(srs_path, srs_data)
    print(f"Removed {modifications} traceability links to create coverage gaps.")

    # 2. Compute Ground Truth (Recalculate after modification)
    # Re-scan to find truly unlinked needs
    
    linked_needs_ids = set()
    
    # Check forward links (NEEDS -> SRS)
    for item in needs_items:
        if 'links' in item:
            for link in item['links']:
                # If NEED links to SRS
                if link.get('docId') == 'SRS': # Simplified check
                    linked_needs_ids.add(str(item['id']))
    
    # Check incoming links (SRS -> NEEDS)
    # We need to re-scan SRS because we modified it
    srs_data_reloaded = load_json(srs_path) # Reload to be safe
    srs_items_re = get_flat_items(srs_data_reloaded.get('data', []))
    
    for item in srs_items_re:
        if 'links' in item:
            for link in item['links']:
                # Identify if link points to NEEDS document
                # In ReqView JSON, docId is the document alias or GUID.
                # We assume 'NEEDS' is the alias used in the example project.
                doc_id_ref = link.get('docId')
                req_id_ref = str(link.get('reqId'))
                
                # We consider it linked if it points to NEEDS document
                # (Simple heuristic: if target ID is in our NEEDS ID list, it's a link to needs)
                if req_id_ref in all_needs_ids:
                    linked_needs_ids.add(req_id_ref)

    # Determine Unlinked Needs
    unlinked_needs = []
    for nid in all_needs_ids:
        if nid not in linked_needs_ids:
            unlinked_needs.append(f"NEEDS-{nid}")
    
    unlinked_needs.sort(key=lambda x: int(x.split('-')[1]))
    
    print(f"Ground Truth Unlinked Needs: {unlinked_needs}")
    
    gt_data = {
        "unlinked_needs": unlinked_needs,
        "total_needs_count": len(all_needs_ids),
        "unlinked_count": len(unlinked_needs)
    }
    
    save_json(gt_path, gt_data)

except Exception as e:
    print(f"Error in python setup script: {e}")
    sys.exit(1)

PY_SCRIPT

# 3. Launch Application
# Kill any existing ReqView
pkill -f "reqview" 2>/dev/null || true
sleep 1

# Launch
launch_reqview_with_project "$PROJECT_DIR"
sleep 5

# Ensure nice state
dismiss_dialogs
maximize_window

# Start with NEEDS document open? Or closed to force navigation?
# Task says "Open the NEEDS document", so we'll leave it at project root or open SRS.
# Let's open the project view but no specific document to force the agent to find it.
# (launch_reqview_with_project already does this).

# Take evidence screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Setup complete ==="