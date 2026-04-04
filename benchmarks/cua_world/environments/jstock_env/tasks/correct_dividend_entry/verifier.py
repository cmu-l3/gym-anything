#!/usr/bin/env python3
"""
Verifier for correct_dividend_entry task in JStock.
Verifies that the MSFT dividend transaction amount was updated from 7.50 to 75.00.
"""

import json
import base64
import csv
import io
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_correct_dividend_entry(traj, env_info, task_info):
    """
    Verify the dividend entry correction.
    
    Criteria:
    1. dividendsummary.csv exists and was modified during task (20 pts)
    2. MSFT dividend amount is exactly 75.00 (or 75.0) (60 pts)
    3. Old incorrect amount (7.50) is gone (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_amount = float(metadata.get('expected_amount', 75.0))
    incorrect_amount = float(metadata.get('incorrect_amount', 7.5))
    target_symbol = metadata.get('target_symbol', 'MSFT')
    
    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. File Modification Check
    if result.get('file_modified', False):
        score += 20
        feedback_parts.append("File modified successfully")
    elif result.get('file_exists', False):
        feedback_parts.append("File exists but was not modified (timestamp unchanged)")
    else:
        return {"passed": False, "score": 0, "feedback": "Dividend file not found"}

    # 2. Content Analysis
    content_b64 = result.get('file_content_base64', '')
    if not content_b64:
        return {"passed": False, "score": score, "feedback": "File content is empty"}
        
    try:
        content_str = base64.b64decode(content_b64).decode('utf-8')
        csv_reader = csv.DictReader(io.StringIO(content_str))
        
        msft_found = False
        correct_value_found = False
        incorrect_value_remain = False
        
        for row in csv_reader:
            # JStock CSV keys: "Code","Symbol","Date","Amount","Comment"
            # Keys might have extra quotes or whitespace depending on parser, but standard CSV lib handles it usually.
            # JStock sometimes quotes keys in file.
            
            code = row.get('Code', '').strip() or row.get('"Code"', '').strip()
            amount_str = row.get('Amount', '').strip() or row.get('"Amount"', '').strip()
            
            if target_symbol in code:
                msft_found = True
                try:
                    amount = float(amount_str)
                    if abs(amount - expected_amount) < 0.01:
                        correct_value_found = True
                    elif abs(amount - incorrect_amount) < 0.01:
                        incorrect_value_remain = True
                except ValueError:
                    pass
        
        if correct_value_found:
            score += 60
            feedback_parts.append(f"Correct amount {expected_amount} found for {target_symbol}")
        elif incorrect_value_remain:
            feedback_parts.append(f"Incorrect amount {incorrect_amount} still present")
        elif msft_found:
            feedback_parts.append(f"Entry found but value mismatch")
        else:
            feedback_parts.append(f"Target entry {target_symbol} not found in file")
            
        if not incorrect_value_remain and msft_found:
             score += 20
             feedback_parts.append("Old incorrect value removed")
             
    except Exception as e:
        feedback_parts.append(f"Error parsing CSV: {e}")

    # 3. VLM Verification (Bonus/Confirmation)
    # If the programmatic check passed, we use VLM just to ensure the UI looks right
    # If programmatic failed, VLM might give partial credit if UI shows correct value but save failed
    
    final_score = score
    passed = final_score >= 100
    
    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback_parts)
    }