#!/usr/bin/env python3
"""
Verifier for inventory_supply_chain_traceability task.
Checks if the agent identified the correct Lot, Vendor, and Purchase Order.
"""

import json
import os
import re

def verify_inventory_supply_chain_traceability(traj, env_info, task_info):
    # 1. Setup - Load data from env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    import tempfile
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    report_exists = result.get("report_exists", False)
    content = result.get("report_content", "").lower()
    ground_truth = result.get("ground_truth", {})

    target_lot = ground_truth.get("target_lot", "").lower()
    target_vendor = ground_truth.get("target_vendor", "").lower()
    target_po = ground_truth.get("target_po", "").lower()

    # 3. Verification Logic
    score = 0
    feedback = []

    if not report_exists:
        return {"passed": False, "score": 0, "feedback": "Report file 'investigation_report.txt' not found on Desktop."}
    
    score += 10
    feedback.append("Report file created.")

    # Check Lot Number (30 pts)
    if target_lot in content:
        score += 30
        feedback.append(f"Correct Lot identified ({ground_truth['target_lot']}).")
    else:
        feedback.append(f"Failed to identify correct Lot (Expected {ground_truth['target_lot']}).")

    # Check Vendor (30 pts)
    # Simple substring match
    if target_vendor in content:
        score += 30
        feedback.append(f"Correct Vendor identified ({ground_truth['target_vendor']}).")
    else:
        feedback.append(f"Failed to identify correct Vendor (Expected {ground_truth['target_vendor']}).")

    # Check PO (30 pts)
    if target_po in content:
        score += 30
        feedback.append(f"Correct Purchase Order identified ({ground_truth['target_po']}).")
    else:
        feedback.append(f"Failed to identify correct PO (Expected {ground_truth['target_po']}).")

    # 4. Final Result
    passed = score >= 70  # Need at least Lot+Vendor or Vendor+PO or Lot+PO roughly
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }