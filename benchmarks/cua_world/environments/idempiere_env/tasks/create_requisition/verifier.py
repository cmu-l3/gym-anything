#!/usr/bin/env python3
"""
Verifier for create_requisition@1 task.
Verifies that the agent created and completed a material requisition in iDempiere
with specific header and line item details.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_requisition(traj, env_info, task_info):
    """
    Verify the requisition creation task.
    
    Scoring Criteria (Total 100):
    1. Requisition Exists (15 pts) - Matches description
    2. Document Completed (15 pts) - Status = 'CO'
    3. Header Dates Correct (10 pts) - Doc Date & Required Date
    4. Line Count Correct (10 pts) - Exactly 2 lines
    5. Line 1 Correct (15 pts) - Azalea Bush, Qty 50
    6. Line 2 Correct (15 pts) - Elm Tree, Qty 25
    7. Anti-Gaming (20 pts) - Count increased, Created after start, Correct Client
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve expected values from metadata (robustness)
    metadata = task_info.get('metadata', {})
    expected_doc_status = metadata.get('expected_doc_status', 'CO')
    expected_date_doc = metadata.get('expected_date_doc', '2024-07-15')
    expected_date_required = metadata.get('expected_date_required', '2024-08-01')
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # Parse Result Data
    req_found = result.get('requisition_found', False)
    details = result.get('requisition_details', {})
    task_start = result.get('task_start_epoch', 0)
    
    # --- Criterion 1: Requisition Exists (15 pts) ---
    if req_found:
        score += 15
        feedback_parts.append("Requisition found")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No requisition found with description 'Seasonal stock replenishment - Summer 2024'"
        }

    # --- Criterion 2: Document Completed (15 pts) ---
    doc_status = details.get('doc_status', '')
    if doc_status == expected_doc_status:
        score += 15
        feedback_parts.append("Document completed (CO)")
    elif doc_status == "IP":
        score += 8
        feedback_parts.append("Document In Progress (partial)")
    else:
        feedback_parts.append(f"Incorrect status: {doc_status}")

    # --- Criterion 3: Header Dates (10 pts) ---
    # Doc Date (5 pts)
    if details.get('date_doc') == expected_date_doc:
        score += 5
    else:
        feedback_parts.append(f"Wrong Doc Date ({details.get('date_doc')})")
        
    # Required Date (5 pts)
    if details.get('date_required') == expected_date_required:
        score += 5
    else:
        feedback_parts.append(f"Wrong Required Date ({details.get('date_required')})")

    # --- Criterion 4: Line Count (10 pts) ---
    line_count = details.get('line_count', 0)
    if line_count == 2:
        score += 10
    else:
        feedback_parts.append(f"Line count mismatch (found {line_count}, expected 2)")

    # --- Criteria 5 & 6: Line Items (30 pts) ---
    lines = details.get('lines', [])
    
    # Helper to find line by product name (fuzzy match)
    def find_line(prod_name_part):
        for line in lines:
            if prod_name_part.lower() in line.get('product', '').lower():
                return line
        return None

    # Line 1: Azalea Bush, Qty 50
    azalea = find_line("Azalea Bush")
    if azalea:
        if int(azalea.get('qty', 0)) == 50:
            score += 15
            feedback_parts.append("Azalea line correct")
        else:
            score += 7 # Partial for finding product but wrong qty
            feedback_parts.append(f"Azalea qty wrong ({azalea.get('qty')})")
    else:
        feedback_parts.append("Azalea Bush missing")

    # Line 2: Elm Tree, Qty 25
    elm = find_line("Elm Tree")
    if elm:
        if int(elm.get('qty', 0)) == 25:
            score += 15
            feedback_parts.append("Elm line correct")
        else:
            score += 7
            feedback_parts.append(f"Elm qty wrong ({elm.get('qty')})")
    else:
        feedback_parts.append("Elm Tree missing")

    # --- Criterion 7: Anti-Gaming (20 pts) ---
    # Created after task start (10 pts)
    created_epoch = details.get('created_epoch', 0)
    if created_epoch >= task_start:
        score += 10
    else:
        feedback_parts.append("Creation time invalid (pre-existing?)")
        
    # Count increased (5 pts)
    if result.get('final_req_count', 0) > result.get('initial_req_count', 0):
        score += 5
    else:
        feedback_parts.append("Total count did not increase")
        
    # Correct Client ID (5 pts)
    # GardenWorld client ID is typically 11
    if str(details.get('ad_client_id')) == "11":
        score += 5
    else:
        feedback_parts.append("Wrong Client ID")

    # Final result calculation
    # Threshold 60 matches the task definition
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }