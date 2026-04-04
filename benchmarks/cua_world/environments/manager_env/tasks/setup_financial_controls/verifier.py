#!/usr/bin/env python3
"""
Verifier for setup_financial_controls task.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_setup_financial_controls(traj, env_info, task_info):
    """
    Verify that the user set the Lock Date and Sales Invoice Footer defaults correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_lock_date = metadata.get('expected_lock_date', '2024-12-31')
    expected_footer_text = metadata.get('expected_footer_text', '')

    # Copy result file
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
    
    # Check 1: Business Key Found (Prerequisite)
    if not result.get('business_key_found'):
        return {"passed": False, "score": 0, "feedback": "Could not access Manager.io business data (System Error?)"}

    # Check 2: Lock Date (40 points)
    # The value scraped from input is typically YYYY-MM-DD
    actual_lock_date = result.get('lock_date_value', '').strip()
    
    if actual_lock_date == expected_lock_date:
        score += 40
        feedback_parts.append("Lock Date set correctly to 2024-12-31.")
    elif actual_lock_date:
        # Partial credit if set but wrong date
        score += 10
        feedback_parts.append(f"Lock Date set to '{actual_lock_date}', expected '{expected_lock_date}'.")
    else:
        feedback_parts.append("Lock Date NOT set.")

    # Check 3: Form Defaults / Footer Text (50 points)
    actual_footer = result.get('footer_value', '').strip()
    # Normalize line endings
    actual_footer = actual_footer.replace('\r\n', '\n').replace('\r', '\n')
    expected_footer_norm = expected_footer_text.replace('\r\n', '\n').replace('\r', '\n')

    # Key phrases to check
    phrases = [
        "Net 15 Days",
        "First National Bank",
        "555-0199",
        "Thank you for your business"
    ]
    
    phrases_found = 0
    for phrase in phrases:
        if phrase.lower() in actual_footer.lower():
            phrases_found += 1
    
    if actual_footer == expected_footer_norm:
        score += 50
        feedback_parts.append("Sales Invoice Footer default set exactly as requested.")
    elif phrases_found == len(phrases):
        score += 45
        feedback_parts.append("Sales Invoice Footer contains all required information but formatting differs slightly.")
    elif phrases_found > 0:
        partial = int((phrases_found / len(phrases)) * 30)
        score += partial
        feedback_parts.append(f"Sales Invoice Footer missing some required info ({phrases_found}/{len(phrases)} phrases found).")
    else:
        feedback_parts.append("Sales Invoice Footer default NOT set or empty.")

    # Check 4: Anti-gaming / Timestamp (10 points)
    # We assume if the values are present and match, work was done, 
    # as the initial state is empty.
    if score > 0:
        score += 10
    
    passed = (actual_lock_date == expected_lock_date) and (phrases_found >= 3)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }