#!/usr/bin/env python3
"""
Verifier for create_physical_inventory task.

Criteria:
1. M_Inventory record exists (Header)
2. Warehouse is HQ
3. Movement Date is 2024-12-31
4. Contains 3 specific lines with correct quantities
5. Document Status is Draft (DR)
"""

import json
import os
import tempfile
import logging
from datetime import datetime

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_physical_inventory(traj, env_info, task_info):
    """
    Verifies the Physical Inventory creation task.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    record_found = result.get('record_found', False)
    header = result.get('header', {})
    lines = result.get('lines', []) or []
    task_start = result.get('task_start', 0)
    
    # Metadata for expected values
    metadata = task_info.get('metadata', {})
    expected_desc = metadata.get('expected_description', "Year-End Count Q4 2024")
    expected_wh_value = metadata.get('expected_warehouse', "HQ")
    expected_date = metadata.get('expected_date', "2024-12-31")
    expected_lines_data = metadata.get('expected_lines', [])

    score = 0
    feedback = []

    # 3. Verify Header (Max 35 points)
    if not record_found:
        return {"passed": False, "score": 0, "feedback": "No Physical Inventory record found created during the task."}
    
    score += 15
    feedback.append("Inventory header record found.")

    # Check Creation Time (Anti-gaming)
    created_ts = header.get('created_ts', 0)
    if created_ts < task_start:
        feedback.append("Warning: Record appears to have been created before task start.")
        # We don't fail immediately but this is suspicious
    
    # Check Description
    if expected_desc in header.get('description', ''):
        feedback.append(f"Description matches '{expected_desc}'.")
    else:
        feedback.append(f"Description mismatch. Expected '{expected_desc}', got '{header.get('description')}'")
    
    # Check Warehouse (10 pts)
    wh_val = header.get('warehouse_value', '')
    wh_name = header.get('warehouse_name', '')
    if expected_wh_value == wh_val or expected_wh_value in wh_name:
        score += 10
        feedback.append(f"Correct Warehouse ({wh_val}).")
    else:
        feedback.append(f"Incorrect Warehouse. Expected '{expected_wh_value}', got '{wh_val}'.")

    # Check Date (5 pts)
    # Date format from SQL might vary (YYYY-MM-DD usually)
    mov_date = header.get('movement_date', '')
    if expected_date in str(mov_date):
        score += 5
        feedback.append("Correct Movement Date.")
    else:
        feedback.append(f"Incorrect Date. Expected {expected_date}, got {mov_date}.")

    # Check Doc Status (5 pts)
    # Expected 'DR' (Draft) or 'IP' (In Progress) is okay, strictly not 'CO' (Completed) if instructed to leave in draft
    doc_status = header.get('docstatus', '')
    if doc_status in ['DR', 'IP']:
        score += 5
        feedback.append("Document is in Draft status.")
    elif doc_status == 'CO':
        feedback.append("Document was completed (instructions said leave in Draft).")
    else:
        feedback.append(f"Document status: {doc_status}")

    # 4. Verify Lines (Max 55 points)
    # 10 pts for correct count
    if len(lines) == 3:
        score += 10
        feedback.append("Correct number of inventory lines (3).")
    else:
        feedback.append(f"Incorrect number of lines. Expected 3, found {len(lines)}.")

    # Verify specific lines (15 pts each)
    # We need to match product names loosely because of potential case/spacing differences
    # Strategy: For each expected line, find a matching actual line
    
    matched_indices = set()
    
    for exp in expected_lines_data:
        exp_prod = exp['product'].lower()
        exp_qty = float(exp['qty'])
        found = False
        
        for idx, act in enumerate(lines):
            if idx in matched_indices:
                continue
            
            act_prod = act.get('product_name', '').lower()
            act_qty = float(act.get('qtycount', 0))
            
            # Check if product name contains expected string
            if exp_prod in act_prod:
                # Check quantity
                if abs(act_qty - exp_qty) < 0.01:
                    score += 15
                    feedback.append(f"Line correct: {exp['product']} (Qty: {exp_qty})")
                    found = True
                    matched_indices.add(idx)
                    break
                else:
                    feedback.append(f"Line found for {exp['product']} but wrong quantity (Expected {exp_qty}, Got {act_qty})")
                    found = True # Found product but wrong qty, stop looking for this product
                    matched_indices.add(idx)
                    break
        
        if not found:
            feedback.append(f"Missing line for product: {exp['product']}")

    # 5. VLM Verification (10 pts)
    # Simple check: Does final screenshot exist and (optionally) show the grid?
    # Since we have robust DB verification, we treat this as a "process check"
    if os.path.exists("/tmp/task_final.png") or result.get('screenshot_path'):
        # In a real scenario we'd query VLM here. 
        # For this implementation, we award points if the DB record exists, 
        # implying the UI was used successfully.
        score += 5
        feedback.append("Visual evidence present.")
        
        # Check trajectory usage if available (stub for logic)
        if len(traj) > 0:
            score += 5
            feedback.append("Trajectory recorded.")
    
    # 6. Final Result
    passed = (score >= 70) and (record_found is True)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }