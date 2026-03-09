#!/usr/bin/env python3
"""
Verifier for setup_tax_codes task.
"""

import json
import logging
import tempfile
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_setup_tax_codes(traj, env_info, task_info):
    """
    Verifies that the VAT tax codes were correctly created in Manager.io.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Score Calculation
    score = 0
    feedback_parts = []
    
    # Check 1: Settings/Tax Codes Page Accessibility (10 pts)
    if result.get("page_accessible"):
        score += 10
        feedback_parts.append("Navigated to Tax Codes")
    else:
        feedback_parts.append("Failed to access Tax Codes settings")
    
    found_codes = result.get("tax_codes_found", [])
    
    # Check 2: Standard Rate Code (35 pts total)
    std_code = next((c for c in found_codes if "UK Standard Rate" in c["name"]), None)
    if std_code:
        score += 20
        feedback_parts.append("Standard Rate code found")
        if abs(std_code["rate"] - 20.0) < 0.1:
            score += 15
            feedback_parts.append("Standard Rate correct (20%)")
        else:
            feedback_parts.append(f"Standard Rate incorrect ({std_code['rate']}%)")
    else:
        feedback_parts.append("Standard Rate code MISSING")
        
    # Check 3: Reduced Rate Code (35 pts total)
    red_code = next((c for c in found_codes if "UK Reduced Rate" in c["name"]), None)
    if red_code:
        score += 20
        feedback_parts.append("Reduced Rate code found")
        if abs(red_code["rate"] - 5.0) < 0.1:
            score += 15
            feedback_parts.append("Reduced Rate correct (5%)")
        else:
            feedback_parts.append(f"Reduced Rate incorrect ({red_code['rate']}%)")
    else:
        feedback_parts.append("Reduced Rate code MISSING")

    # Check 4: Anti-gaming / Visual Confirmation (20 pts)
    # We rely on the scraper's existence check. In a full VLM setup, we'd also check screenshots.
    # Here we give points if we found exactly the expected items to encourage clean work.
    if len(found_codes) == 2:
        score += 20
        feedback_parts.append("Correct number of tax codes found")
    elif len(found_codes) > 2:
        score += 10
        feedback_parts.append("Tax codes found, but extras exist (did not start clean?)")
    
    passed = score >= 70 and std_code and red_code
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }