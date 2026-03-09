#!/usr/bin/env python3
"""
Verifier for configure_holiday_list task.

Verifies:
1. Existence of the holiday list "US Corporate Holidays 2025"
2. Existence of the 8 specific holidays with correct dates
3. Anti-gaming checks (database record creation)
"""

import json
import os
import logging
import tempfile
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_holiday_list(traj, env_info, task_info):
    """
    Verify the holiday list creation using DB export data.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
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

    score = 0
    max_score = 100
    feedback = []

    # 1. Verify List Existence (20 pts)
    if result.get('list_found', False):
        score += 20
        feedback.append("Holiday list 'US Corporate Holidays 2025' found.")
    else:
        # Fallback: if list count increased but specific name query failed (maybe typo), give partial credit
        diff = result.get('list_count_diff', 0)
        try:
            diff = int(diff)
        except:
            diff = 0
            
        if diff > 0:
            score += 10
            feedback.append("A new holiday list was created, but the name did not match exactly.")
        else:
            feedback.append("Holiday list not found.")

    # 2. Verify Holidays (10 pts per pair = 40 pts)
    # Expected dates
    # Pairs: (Jan 1, Jan 20), (Feb 17, May 26), (Jul 4, Sep 1), (Nov 27, Dec 25)
    
    holidays_details = result.get('holidays_details', [])
    found_dates = [h['date'] for h in holidays_details if h.get('found', False)]
    
    # Mapping for checking
    # 2025-01-01
    # 2025-01-20
    # 2025-02-17
    # 2025-05-26
    # 2025-07-04
    # 2025-09-01
    # 2025-11-27
    # 2025-12-25
    
    found_count = len(found_dates)
    
    # Score based on pairs roughly
    pair_score = 0
    if "2025-01-01" in found_dates and "2025-01-20" in found_dates: pair_score += 10
    elif "2025-01-01" in found_dates or "2025-01-20" in found_dates: pair_score += 5
    
    if "2025-02-17" in found_dates and "2025-05-26" in found_dates: pair_score += 10
    elif "2025-02-17" in found_dates or "2025-05-26" in found_dates: pair_score += 5

    if "2025-07-04" in found_dates and "2025-09-01" in found_dates: pair_score += 10
    elif "2025-07-04" in found_dates or "2025-09-01" in found_dates: pair_score += 5

    if "2025-11-27" in found_dates and "2025-12-25" in found_dates: pair_score += 10
    elif "2025-11-27" in found_dates or "2025-12-25" in found_dates: pair_score += 5
    
    score += pair_score
    feedback.append(f"Holidays found: {found_count}/8 ({pair_score}/40 pts).")

    # 3. Verify Coverage (20 pts for 6+, 20 pts for 8)
    coverage_score = 0
    if found_count >= 6:
        coverage_score += 20
        feedback.append("Good coverage (6+ holidays).")
    
    if found_count >= 8:
        coverage_score += 20
        feedback.append("Perfect coverage (8 holidays).")
        
    score += coverage_score

    # Pass Threshold
    passed = score >= 50 and (result.get('list_found', False) or found_count >= 4)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": {
            "found_dates": found_dates,
            "list_found": result.get('list_found', False)
        }
    }