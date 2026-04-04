#!/usr/bin/env python3
"""
Verifier for fix_store_issues task.

Scoring (100 points total):
1. Samsung Product Published (25 pts): status == 1
2. Store Email Corrected (25 pts): mail == 'store@urbanelectronics.com'
3. Promotion Extended (25 pts): end_date contains '2025-12-31'
4. User Unblocked (25 pts): status == 1

Pass Threshold: 50 points (2/4 fixes)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_fix_store_issues(traj, env_info, task_info):
    """
    Verify that the 4 reported store issues have been fixed.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define targets
    TARGET_EMAIL = "store@urbanelectronics.com"
    TARGET_DATE = "2025-12-31"
    
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/fix_store_issues_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except FileNotFoundError:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Result file not found - export may have failed"
        }
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Error reading result file: {e}"
        }

    score = 0
    feedback_parts = []
    
    # 1. Verify Product Status (25 pts)
    # status should be 1 (published)
    # The setup script sets it to 0.
    prod_status = int(result.get("product_status", 0))
    if prod_status == 1:
        score += 25
        feedback_parts.append("Product published (Success)")
    else:
        feedback_parts.append("Product still unpublished")

    # 2. Verify Store Email (25 pts)
    # mail should be 'store@urbanelectronics.com'
    # Setup sets it to 'stoer@...'
    actual_email = result.get("store_email", "").strip()
    if actual_email == TARGET_EMAIL:
        score += 25
        feedback_parts.append("Store email fixed (Success)")
    else:
        feedback_parts.append(f"Store email incorrect: '{actual_email}'")

    # 3. Verify Promotion End Date (25 pts)
    # end_date should be '2025-12-31'
    # Setup sets it to '2024-01-01'
    # Date string might contain time (e.g. 2025-12-31T23:59:59), check containment
    actual_date = result.get("promo_end_date", "")
    if TARGET_DATE in actual_date:
        score += 25
        feedback_parts.append("Promotion date extended (Success)")
    else:
        feedback_parts.append(f"Promotion date incorrect: '{actual_date}'")

    # 4. Verify User Status (25 pts)
    # status should be 1 (active)
    # Setup sets it to 0
    user_status = int(result.get("user_status", 0))
    if user_status == 1:
        score += 25
        feedback_parts.append("User unblocked (Success)")
    else:
        feedback_parts.append("User still blocked")

    # Final scoring
    # Pass if score >= 50 (at least 2 fixes)
    passed = score >= 50
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }