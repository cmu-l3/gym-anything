#!/usr/bin/env python3
"""
Verifier for create_customer_shipment task.

Criteria:
1. Shipment record exists (created during task) [15pts]
2. Business Partner is "C&W Construction" [15pts]
3. Line 1: "Azalea Bush" exists [15pts]
4. Line 1: Quantity is 25 [10pts]
5. Line 2: "Elm Tree" exists [15pts]
6. Line 2: Quantity is 10 [10pts]
7. Document Status is Completed (CO) [15pts]
8. Anti-gaming (timestamp check) [5pts]

Total: 100pts
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_customer_shipment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load Metadata
    metadata = task_info.get('metadata', {})
    expected_bp = metadata.get('expected_bp_name', 'C&W Construction')
    expected_docstatus = metadata.get('expected_docstatus', 'CO')
    
    # Retrieve result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result from container: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check if shipment exists (15 pts)
    if not result.get('shipment_found', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No new customer shipment record found created during the task."
        }
    
    score += 15
    feedback_parts.append("Shipment record created")

    # 2. Check Business Partner (15 pts)
    bp_name = result.get('bp_name', '')
    if expected_bp.lower() in bp_name.lower():
        score += 15
        feedback_parts.append(f"Correct Business Partner ({bp_name})")
    else:
        feedback_parts.append(f"Incorrect Business Partner: expected '{expected_bp}', got '{bp_name}'")

    # 3-6. Check Lines (50 pts total)
    # We look for specific products in the lines list
    lines = result.get('lines', [])
    
    # Helper to find a product line
    def find_line(prod_name):
        for line in lines:
            if prod_name.lower() in line.get('product_name', '').lower():
                return line
        return None

    # Check Azalea Bush
    azalea_line = find_line("Azalea Bush")
    if azalea_line:
        score += 15
        feedback_parts.append("Azalea Bush line found")
        qty = azalea_line.get('quantity', 0)
        if abs(qty - 25) < 0.01:
            score += 10
            feedback_parts.append("Azalea Bush Qty correct (25)")
        else:
            feedback_parts.append(f"Azalea Bush Qty incorrect (expected 25, got {qty})")
    else:
        feedback_parts.append("Azalea Bush line missing")

    # Check Elm Tree
    elm_line = find_line("Elm Tree")
    if elm_line:
        score += 15
        feedback_parts.append("Elm Tree line found")
        qty = elm_line.get('quantity', 0)
        if abs(qty - 10) < 0.01:
            score += 10
            feedback_parts.append("Elm Tree Qty correct (10)")
        else:
            feedback_parts.append(f"Elm Tree Qty incorrect (expected 10, got {qty})")
    else:
        feedback_parts.append("Elm Tree line missing")

    # 7. Check Document Status (15 pts)
    doc_status = result.get('doc_status', '')
    if doc_status == 'CO':
        score += 15
        feedback_parts.append("Document Completed")
    elif doc_status == 'CL':
        score += 15
        feedback_parts.append("Document Closed (Acceptable)")
    elif doc_status == 'DR':
        feedback_parts.append("Document is Draft (not Completed)")
    else:
        feedback_parts.append(f"Document status is {doc_status}")

    # 8. Anti-gaming / Timestamp check (5 pts)
    # The export script already filters for records created >= task_start
    # So if we found a record, it passed the timestamp check.
    score += 5
    feedback_parts.append("Timestamp verified")

    # VLM Verification (Optional backup / Hybrid)
    # If score is very low but VLM thinks they did it, might indicate DB query issue,
    # but for ERP tasks we trust the DB. We use VLM just to check for empty screens/errors.
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        final_screenshot = get_final_screenshot(traj)
        vlm_res = query_vlm(
            prompt="Is this an iDempiere or ERP screen showing a Shipment or Document window? Answer Yes or No.",
            image=final_screenshot
        )
        if vlm_res.get('parsed', {}).get('answer', '').lower() == 'no' and score > 50:
            feedback_parts.append("(Warning: VLM did not recognize ERP screen)")

    passed = (score >= 50)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }