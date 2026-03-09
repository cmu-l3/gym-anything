#!/usr/bin/env python3
"""
Verifier for register_fixed_asset task in Manager.io.

Scoring Criteria:
1. Fixed Assets module enabled (20 pts)
2. Asset record created (20 pts)
3. Correct Asset Name (10 pts)
4. Correct Acquisition Date (10 pts)
5. Correct Cost (10 pts)
6. Correct Depreciation Method (15 pts)
7. Correct Useful Life/Rate (10 pts)
8. Correct Salvage Value (5 pts)

Total: 100 pts
Pass Threshold: 55 pts (must have enabled module and created asset)
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_register_fixed_asset(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Expected values
    metadata = task_info.get('metadata', {})
    exp_name = metadata.get('expected_name', "Bosch CDR 900 Diagnostic System")
    exp_cost = float(metadata.get('expected_cost', 8500))
    exp_date = metadata.get('expected_date', "2024-07-15")
    exp_salvage = float(metadata.get('expected_salvage', 500))
    exp_life = float(metadata.get('expected_life_months', 60))
    
    # Load result
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

    score = 0
    feedback = []
    
    # 1. Module Enabled (20 pts)
    if result.get('module_enabled'):
        score += 20
        feedback.append("Fixed Assets module enabled.")
    else:
        feedback.append("Fixed Assets module NOT enabled.")

    # 2. Asset Exists (20 pts)
    if result.get('asset_found'):
        score += 20
        feedback.append("Asset record found.")
    else:
        feedback.append("Asset record NOT found.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    details = result.get('asset_details', {})
    
    # 3. Asset Name (10 pts)
    name = details.get('Name', '')
    if exp_name.lower() in name.lower() and len(name) > 5:
        score += 10
        feedback.append("Asset name correct.")
    else:
        feedback.append(f"Asset name mismatch: '{name}' vs '{exp_name}'")

    # 4. Acquisition Date (10 pts)
    date_val = details.get('AcquisitionDate', '')
    if date_val == exp_date:
        score += 10
        feedback.append("Date correct.")
    else:
        # Check standard format variations if needed
        feedback.append(f"Date mismatch: '{date_val}' vs '{exp_date}'")

    # 5. Cost (10 pts)
    try:
        cost_val = float(details.get('AcquisitionCost', 0))
        if abs(cost_val - exp_cost) < 1.0:
            score += 10
            feedback.append("Cost correct.")
        else:
            feedback.append(f"Cost mismatch: {cost_val} vs {exp_cost}")
    except:
        feedback.append("Invalid cost format.")

    # 6. Depreciation Method (15 pts)
    # The export script attempts to detect "StraightLine"
    method = details.get('DepreciationMethod', '')
    if "StraightLine" in method:
        score += 15
        feedback.append("Depreciation method correct.")
    else:
        feedback.append("Depreciation method incorrect or not set.")

    # 7. Useful Life / Rate (10 pts)
    # Manager might store this as Rate or Life depending on version/config
    # 60 months might be stored as '60' or calculated rate
    rate_val = details.get('DepreciationRate', '')
    # If straight line monthly, rate might be input as life in months? 
    # Usually Manager asks for "Custom depreciation rate" or just input.
    # We accept 60 or 5 (years) or close equivalents
    if rate_val == '60' or rate_val == '5':
        score += 10
        feedback.append("Useful life correct.")
    else:
        feedback.append(f"Useful life/rate mismatch: '{rate_val}'")

    # 8. Salvage Value (5 pts)
    try:
        salvage_val = float(details.get('SalvageValue', 0))
        if abs(salvage_val - exp_salvage) < 1.0:
            score += 5
            feedback.append("Salvage value correct.")
        else:
            feedback.append(f"Salvage value mismatch: {salvage_val} vs {exp_salvage}")
    except:
        feedback.append("Invalid salvage value.")

    return {
        "passed": score >= 55 and result.get('module_enabled') and result.get('asset_found'),
        "score": score,
        "feedback": " ".join(feedback)
    }