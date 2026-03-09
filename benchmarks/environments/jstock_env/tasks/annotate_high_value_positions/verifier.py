#!/usr/bin/env python3
"""
Verifier for annotate_high_value_positions task in JStock.
Verifies that the agent correctly identified high-value positions (>16k)
and annotated them, while leaving others alone.
"""

import json
import tempfile
import os
import logging
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_annotate_high_value_positions(traj, env_info, task_info):
    """
    Verify the portfolio annotation task.
    
    Criteria:
    1. AAPL (Value > 16k): Must have comment "High Value - Review Quarterly" (30 pts)
    2. MSFT (Value > 16k): Must have comment "High Value - Review Quarterly" (30 pts)
    3. NVDA (Value < 16k): Must have empty comment (20 pts)
    4. File Modified: The portfolio file must have been updated during task (10 pts)
    5. Data Integrity: Purchase Prices/Units must not be changed (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    target_comment = metadata.get('target_comment', "High Value - Review Quarterly")
    
    # Setup temporary file for result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Check if file exists and was modified
    if not result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Portfolio file not found."}

    file_mtime = result.get('file_mtime', 0)
    task_start = result.get('task_start', 0)
    
    if file_mtime > task_start:
        score += 10
        feedback_parts.append("Portfolio file modified during task.")
    else:
        feedback_parts.append("Portfolio file NOT modified (Action not saved?).")

    # 2. Analyze Portfolio Data
    data = result.get('data', [])
    if not data:
        return {"passed": False, "score": score, "feedback": "Portfolio file is empty."}

    # Helper to find stock data
    stocks = {row.get('Code', ''): row for row in data}
    
    # Check AAPL (Target)
    aapl = stocks.get('AAPL')
    if aapl:
        comment = aapl.get('Comment', '').strip()
        if comment == target_comment:
            score += 30
            feedback_parts.append("AAPL annotated correctly.")
        else:
            feedback_parts.append(f"AAPL incorrect comment: '{comment}' (Expected: '{target_comment}').")
            
        # Integrity Check
        try:
            if float(aapl.get('Units', 0)) == 100.0 and float(aapl.get('Purchase Price', 0)) == 185.2:
                # Part of integrity score, accumulated later
                pass
            else:
                feedback_parts.append("AAPL financial data altered!")
        except:
            pass
    else:
        feedback_parts.append("AAPL missing from portfolio!")

    # Check MSFT (Target)
    msft = stocks.get('MSFT')
    if msft:
        comment = msft.get('Comment', '').strip()
        if comment == target_comment:
            score += 30
            feedback_parts.append("MSFT annotated correctly.")
        else:
            feedback_parts.append(f"MSFT incorrect comment: '{comment}'.")
    else:
        feedback_parts.append("MSFT missing from portfolio!")

    # Check NVDA (Non-Target)
    nvda = stocks.get('NVDA')
    if nvda:
        comment = nvda.get('Comment', '').strip()
        if not comment: # Empty string or None
            score += 20
            feedback_parts.append("NVDA correctly ignored (no comment).")
        elif "High Value" in comment:
            feedback_parts.append(f"NVDA incorrectly annotated: '{comment}' (Value < 16k).")
        else:
            # Maybe they added a different note? acceptable if it doesn't match target
            score += 10
            feedback_parts.append(f"NVDA has unrelated comment: '{comment}'.")
    else:
        feedback_parts.append("NVDA missing from portfolio!")

    # Integrity Check (Global) - 10 pts
    # We check if the basic structure is intact (count of stocks and basic values)
    integrity_passed = True
    if len(stocks) != 3:
        integrity_passed = False
    
    if integrity_passed and aapl and msft and nvda:
        # Check values roughly match expected (parsing strings to floats)
        try:
            if (float(aapl.get('Purchase Value', 0)) == 18520.0 and 
                float(msft.get('Purchase Value', 0)) == 18725.0 and 
                float(nvda.get('Purchase Value', 0)) == 15382.5):
                score += 10
                feedback_parts.append("Financial data integrity maintained.")
            else:
                feedback_parts.append("Financial values modified.")
        except ValueError:
             feedback_parts.append("Error parsing financial data.")
    else:
         feedback_parts.append("Portfolio structure altered (missing stocks).")

    # Final Result
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }