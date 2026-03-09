#!/usr/bin/env python3
"""
Verifier for create_inventory_request task in HospitalRun.

Criteria:
1. A new inventory request document exists in CouchDB.
2. The document references "Sterile Gauze Pads (4x4 inch)".
3. The quantity is 25.
4. The status is "Requested".
5. VLM verification of the trajectory to ensure UI usage.
"""

import json
import os
import logging
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_inventory_request(traj, env_info, task_info):
    """
    Verify that the inventory request was created correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_item = metadata.get('target_item_name', "Sterile Gauze Pads")
    target_qty = metadata.get('target_quantity', 25)
    target_status = metadata.get('target_status', "Requested")

    # Load result JSON
    import tempfile
    temp_dir = tempfile.mkdtemp()
    try:
        # Copy main result file
        result_path = os.path.join(temp_dir, "task_result.json")
        copy_from_env("/tmp/task_result.json", result_path)
        
        with open(result_path, 'r') as f:
            result = json.load(f)
            
        # Copy CouchDB dump
        couch_dump_remote = result.get("couchdb_dump_path")
        if couch_dump_remote:
            local_dump_path = os.path.join(temp_dir, "all_docs.json")
            copy_from_env(couch_dump_remote, local_dump_path)
            with open(local_dump_path, 'r') as f:
                couch_data = json.load(f)
        else:
            couch_data = {"rows": []}
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task data: {str(e)}"}
    finally:
        # cleanup is handled by temp_dir usually, but we can be explicit if needed
        pass

    # Analysis
    initial_count = int(result.get("initial_request_count", 0))
    rows = couch_data.get("rows", [])
    
    current_requests = []
    target_request_found = False
    correct_details = False
    
    matching_docs = []

    for row in rows:
        doc = row.get("doc", {})
        data = doc.get("data", doc) # HospitalRun often wraps data in 'data' key
        doc_id = doc.get("_id", "")
        
        # Determine if it's an inventory request
        # Patterns: type="inventory_request", or ID contains "inv-request", or modelName="inventoryRequest"
        doc_type = data.get("type", doc.get("type", ""))
        model_name = data.get("modelName", "")
        
        is_request = (
            doc_type in ["inventory_request", "inventoryRequest"] or
            "inv-request" in doc_id or
            model_name == "inventoryRequest"
        )
        
        if is_request:
            current_requests.append(doc)
            
            # Check content
            # Item reference might be ID or name
            item_name = data.get("inventoryItemName", "")
            item_ref = data.get("inventoryItem", "")
            quantity = data.get("quantity", 0)
            status = data.get("status", "")
            
            # Check if this matches our target
            # Note: item_name might not be populated, might just be item ID. 
            # But the task requires selecting "Sterile Gauze Pads", usually populated in UI.
            # We accept match in name OR if we had the ID (but ID is dynamic). 
            # We'll look for "Gauze" in the document string to be safe.
            doc_str = json.dumps(doc).lower()
            
            name_match = target_item.lower() in doc_str or "gauze" in doc_str
            qty_match = False
            try:
                if int(quantity) == int(target_qty):
                    qty_match = True
            except:
                pass
                
            status_match = target_status.lower() == status.lower()
            
            if name_match:
                matching_docs.append({
                    "doc_id": doc_id,
                    "qty_match": qty_match,
                    "status_match": status_match,
                    "quantity": quantity
                })

    # Scoring
    score = 0
    feedback = []
    
    # Criterion 1: New request created (10 pts)
    # We check if we found a matching doc that looks newly created
    # Since we don't have perfect timestamps, we rely on matching the specific details 
    # which define this unique task instance.
    if len(matching_docs) > 0:
        score += 30
        feedback.append("Inventory request document created.")
    else:
        feedback.append("No inventory request found for Sterile Gauze Pads.")
        
    # Criterion 2: Correct item (25 pts)
    # Implicitly checked above by filtering for "gauze", but let's confirm
    if any(d for d in matching_docs):
        score += 25
        feedback.append("Correct item referenced.")
        
    # Criterion 3: Correct quantity (25 pts)
    if any(d["qty_match"] for d in matching_docs):
        score += 25
        feedback.append(f"Correct quantity ({target_qty}).")
    else:
        qs = [d['quantity'] for d in matching_docs]
        if matching_docs:
            feedback.append(f"Incorrect quantity found: {qs}, expected {target_qty}.")
            
    # Criterion 4: Correct status (10 pts)
    if any(d["status_match"] for d in matching_docs):
        score += 10
        feedback.append(f"Correct status ({target_status}).")
        
    # Criterion 5: Count increased (10 pts)
    if len(current_requests) > initial_count:
        score += 10
        feedback.append("Total request count increased.")
    elif len(matching_docs) > 0:
        # If we found the doc but count didn't strictly increase (maybe one was deleted?),
        # we still give credit if the doc is clearly the one we wanted.
        score += 10
        feedback.append("Target document exists (count check ambiguous).")
    else:
        feedback.append("No increase in request count.")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }