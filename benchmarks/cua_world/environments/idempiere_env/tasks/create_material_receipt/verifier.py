#!/usr/bin/env python3
"""
Verifier for create_material_receipt task.
Verifies that the agent created a correct Material Receipt in iDempiere.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_material_receipt(traj, env_info, task_info):
    """
    Verify the material receipt creation.
    
    Criteria:
    1. Receipt exists and was created after task start (25 pts)
    2. Vendor is 'Seed Farm Inc.' (15 pts)
    3. Description contains 'spring' or 'seed' (10 pts)
    4. Line 1: Azalea Bush, Qty 100 (15 pts)
    5. Line 2: Elm Tree, Qty 50 (15 pts)
    6. Document Status is Completed ('CO') (20 pts)
       - Partial credit for Draft/In Progress
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Initialize score
    score = 0
    feedback = []
    
    # Extract data
    receipt = result.get('latest_receipt', {})
    exists = receipt.get('exists', False)
    task_start = result.get('task_start_time', 0)
    created_time = receipt.get('created_time', 0)
    
    # CRITERION 1: Existence & Timing (25 pts)
    if not exists:
        return {"passed": False, "score": 0, "feedback": "No Material Receipt was created."}
    
    if created_time < task_start:
        feedback.append("Warning: Receipt timestamp is before task start (pre-existing data?)")
        # We proceed but with caution, maybe the clock skew is small, or it's the wrong record
        # In strict anti-gaming, this might zero the score, but we'll award existence points if it's the *latest* one
        score += 10
    else:
        score += 25
        feedback.append("New Material Receipt confirmed.")

    # CRITERION 2: Vendor (15 pts)
    vendor = receipt.get('vendor_name', '').lower()
    if 'seed farm' in vendor:
        score += 15
        feedback.append(f"Correct Vendor ({receipt.get('vendor_name')}).")
    else:
        feedback.append(f"Incorrect Vendor: {receipt.get('vendor_name')} (Expected: Seed Farm Inc.)")

    # CRITERION 3: Description (10 pts)
    desc = receipt.get('description', '').lower()
    if 'spring' in desc or 'seed' in desc:
        score += 10
        feedback.append("Description is correct.")
    elif desc:
        score += 5
        feedback.append(f"Description present but generic ('{receipt.get('description')}').")
    else:
        feedback.append("Description is missing.")

    # CRITERION 4 & 5: Lines (30 pts)
    lines = receipt.get('lines', [])
    azalea_found = False
    elm_found = False
    
    for line in lines:
        prod = line.get('product', '').lower()
        qty = line.get('qty', 0)
        
        # Check Azalea
        if 'azalea' in prod:
            if qty == 100:
                score += 15
                feedback.append("Line: Azalea Bush (100) correct.")
                azalea_found = True
            else:
                score += 5
                feedback.append(f"Line: Azalea Bush found but wrong Qty ({qty}).")
                azalea_found = True
        
        # Check Elm
        if 'elm' in prod:
            if qty == 50:
                score += 15
                feedback.append("Line: Elm Tree (50) correct.")
                elm_found = True
            else:
                score += 5
                feedback.append(f"Line: Elm Tree found but wrong Qty ({qty}).")
                elm_found = True

    if not azalea_found:
        feedback.append("Missing product: Azalea Bush.")
    if not elm_found:
        feedback.append("Missing product: Elm Tree.")

    # CRITERION 6: Doc Status (20 pts)
    status = receipt.get('doc_status', '')
    if status == 'CO': # Completed
        score += 20
        feedback.append("Document Status: Completed.")
    elif status == 'CL': # Closed
        score += 20
        feedback.append("Document Status: Closed (Acceptable).")
    elif status == 'DR': # Draft
        score += 5
        feedback.append("Document Status: Draft (Not completed).")
    elif status == 'IP': # In Progress
        score += 5
        feedback.append("Document Status: In Progress (Not completed).")
    else:
        feedback.append(f"Document Status: {status} (Not completed).")

    # Final tally
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }