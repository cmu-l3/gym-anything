#!/usr/bin/env python3
"""
Verifier for quality_inspection_purchase task.

Criteria:
C1 (20 pts): QI Template 'Shaft Incoming QC' exists with >= 3 parameters having min/max limits.
C2 (15 pts): Shaft item configured for incoming inspection with the new template.
C3 (25 pts): Quality Inspection record submitted, status=Accepted, linked to PR.
C4 (25 pts): Purchase Receipt submitted for Shaft (qty >= 30), linked to Eagle Hardware PO.
C5 (15 pts): Shaft warehouse stock increased by >= 30.

Pass Threshold: 60 pts
"""

import json
import logging
import tempfile
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_quality_inspection_purchase(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", "/tmp/quality_inspection_purchase_result.json")

    # Copy result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_file, temp_result.name)
        with open(temp_result.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result data: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    baseline = data.get("baseline", {})
    po_name = baseline.get("po_name", "")

    qi_template = data.get("qi_template", {})
    item_config = data.get("item_configuration", {})
    quality_inspections = data.get("quality_inspections", [])
    purchase_receipts = data.get("purchase_receipts", [])
    stock_info = data.get("stock_info", {})

    # ERPNext Reachability Check
    if not po_name:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Setup failure: No Purchase Order recorded in baseline. Was ERPNext running?"
        }

    score = 0
    feedback_parts = []

    # C1: Quality Inspection Template
    # Must exist, be named exactly 'Shaft Incoming QC', and have >= 3 parameters with min or max values.
    c1_pass = False
    if qi_template.get("exists") and qi_template.get("name") == "Shaft Incoming QC":
        valid_params = 0
        for p in qi_template.get("parameters", []):
            if p.get("min_value", 0.0) != 0.0 or p.get("max_value", 0.0) != 0.0 or p.get("numeric") == 1:
                valid_params += 1
        
        if valid_params >= 3:
            c1_pass = True
            score += 20
            feedback_parts.append(f"C1 PASS: Template '{qi_template['name']}' created with {valid_params} valid parameters (+20)")
        else:
            feedback_parts.append(f"C1 FAIL: Template exists but only {valid_params} parameters have numeric boundaries (need 3+).")
    else:
        feedback_parts.append("C1 FAIL: Quality Inspection Template 'Shaft Incoming QC' not found.")

    # C2: Item Configuration
    c2_pass = False
    insp_req = item_config.get("inspection_required_before_purchase") in (1, True, "1", "true")
    temp_linked = item_config.get("quality_inspection_template") == "Shaft Incoming QC"
    
    if insp_req and temp_linked:
        c2_pass = True
        score += 15
        feedback_parts.append("C2 PASS: Shaft item properly configured for incoming inspection (+15)")
    else:
        feedback_parts.append(f"C2 FAIL: Item config incorrect (Required: {insp_req}, Template: {item_config.get('quality_inspection_template')})")

    # C3: Quality Inspection Submitted & Accepted
    c3_pass = False
    for qi in quality_inspections:
        if qi.get("status") == "Accepted" and qi.get("reference_type") == "Purchase Receipt":
            c3_pass = True
            score += 25
            feedback_parts.append(f"C3 PASS: Accepted Quality Inspection '{qi.get('name')}' linked to Purchase Receipt found (+25)")
            break
            
    if not c3_pass:
        feedback_parts.append(f"C3 FAIL: No submitted, Accepted Quality Inspection for Shaft linked to a Purchase Receipt (found {len(quality_inspections)} total)")

    # C4: Purchase Receipt Submitted
    c4_pass = False
    for pr in purchase_receipts:
        # Check quantity and linkage to our specific PO
        if pr.get("qty", 0.0) >= 30.0 and pr.get("purchase_order") == po_name:
            c4_pass = True
            score += 25
            feedback_parts.append(f"C4 PASS: Purchase Receipt '{pr.get('pr_name')}' submitted for PO {po_name} (+25)")
            break

    if not c4_pass:
        feedback_parts.append("C4 FAIL: No valid Purchase Receipt for >= 30 Shafts linked to the PO.")

    # C5: Stock Increase
    c5_pass = False
    stock_increase = stock_info.get("stock_increase", 0.0)
    if stock_increase >= 30.0:
        c5_pass = True
        score += 15
        feedback_parts.append(f"C5 PASS: Shaft stock increased by {stock_increase} >= 30 (+15)")
    else:
        feedback_parts.append(f"C5 FAIL: Stock increase {stock_increase} < 30. Current: {stock_info.get('current_stock')}, Initial: {stock_info.get('initial_stock')}.")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }