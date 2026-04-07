#!/usr/bin/env python3
"""
Verifier for create_uom_conversion task.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_uom_conversion(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    
    # Metadata expectations
    expected_name = task_info.get('metadata', {}).get('expected_name', "Retail Box of 24")
    expected_rate = task_info.get('metadata', {}).get('expected_rate', 24)

    # 1. Verify UOM Exists (30 pts)
    if result.get('uom_exists'):
        score += 30
        feedback_parts.append("UOM 'BX24' created")
    else:
        feedback_parts.append("UOM 'BX24' not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Verify UOM Name (10 pts)
    uom_name = result.get('uom_name', '')
    if uom_name.strip() == expected_name:
        score += 10
        feedback_parts.append("Correct UOM Name")
    else:
        feedback_parts.append(f"Incorrect Name: '{uom_name}'")

    # 3. Verify Precision (10 pts)
    try:
        prec = int(result.get('uom_precision', -1))
        if prec == 0:
            score += 10
            feedback_parts.append("Correct Precision (0)")
        else:
            feedback_parts.append(f"Incorrect Precision: {prec} (expected 0)")
    except:
        feedback_parts.append("Invalid precision format")

    # 4. Verify Conversion Record Exists (20 pts)
    if result.get('conversion_exists'):
        score += 20
        feedback_parts.append("Conversion record found")
    else:
        feedback_parts.append("No conversion record found")

    # 5. Verify Conversion Rate (20 pts)
    try:
        rate = float(result.get('conversion_rate', 0))
        if abs(rate - expected_rate) < 0.01:
            score += 20
            feedback_parts.append(f"Correct Rate ({expected_rate})")
        else:
            feedback_parts.append(f"Incorrect Rate: {rate} (expected {expected_rate})")
    except:
        feedback_parts.append("Invalid rate format")

    # 6. Verify Global Conversion (10 pts)
    if result.get('conversion_is_global'):
        score += 10
        feedback_parts.append("Conversion is Global")
    else:
        feedback_parts.append("Conversion is restricted to a specific product (should be global)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }