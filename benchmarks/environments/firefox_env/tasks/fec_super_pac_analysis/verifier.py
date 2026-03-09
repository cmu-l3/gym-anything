#!/usr/bin/env python3
"""
Verifier for FEC Super PAC Analysis task.

Scoring Breakdown (100 points total):
1. Browser Evidence (25 pts)
   - Visited FEC.gov (10 pts)
   - Created 'FEC Research' bookmark folder with 3+ items (15 pts)
2. File Evidence (15 pts)
   - JSON file exists, is valid, and created during task (15 pts)
3. Data Accuracy (60 pts)
   - Correct Committee IDs for all 3 PACs (30 pts, 10 each)
   - Plausible financial data format and values (30 pts, 10 each)

Pass Threshold: 70 points
"""

import json
import logging
import os
import re
import tempfile

logger = logging.getLogger(__name__)

# Expected Committee IDs
EXPECTED_IDS = {
    "make_america_great_again_inc": "C00825851",
    "future_forward_usa_pac": "C00669259",
    "senate_leadership_fund": "C00571703"
}

# Financial minimums (loose checks to ensure they found the main PACs, not small affiliated ones)
MIN_RECEIPTS = 50_000_000       # $50M
MIN_EXPENDITURES = 10_000_000   # $10M
MIN_CASH = 1_000_000            # $1M

def parse_money(value):
    """Parses a currency string like '$123,456.78' into a float."""
    if isinstance(value, (int, float)):
        return float(value)
    if not isinstance(value, str):
        return 0.0
    # Remove $, commas, whitespace
    clean = re.sub(r'[^\d.]', '', value)
    try:
        return float(clean)
    except ValueError:
        return 0.0

def verify_fec_super_pac_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/fec_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # --- Criterion 1: Browser Evidence (25 pts) ---
    fec_visits = result.get('fec_visits', 0)
    if fec_visits > 0:
        score += 10
        feedback.append("Browser history shows visits to FEC.gov (+10)")
    else:
        feedback.append("No visits to FEC.gov found in history (0)")

    folder_exists = result.get('bookmark_folder_exists', 0)
    bookmarks_count = result.get('bookmarks_in_folder', 0)
    
    if folder_exists:
        if bookmarks_count >= 3:
            score += 15
            feedback.append(f"'FEC Research' bookmark folder found with {bookmarks_count} items (+15)")
        else:
            score += 5
            feedback.append(f"'FEC Research' folder found but only has {bookmarks_count} items (needs 3) (+5)")
    else:
        feedback.append("'FEC Research' bookmark folder not found (0)")

    # --- Criterion 2: File Evidence (15 pts) ---
    file_exists = result.get('file_exists', 0)
    file_fresh = result.get('file_fresh', 0)
    user_data = result.get('user_json_content', {})

    if file_exists and file_fresh and user_data:
        score += 15
        feedback.append("Output JSON file exists, is valid, and was created during task (+15)")
    elif file_exists and user_data:
        score += 5
        feedback.append("Output JSON file exists but was not modified during task (+5)")
    else:
        feedback.append("Output JSON file missing or invalid (0)")
        # If no data, stop here
        return {"passed": False, "score": score, "feedback": "; ".join(feedback)}

    # --- Criterion 3: Data Accuracy (60 pts) ---
    # Check each committee
    committees = ["make_america_great_again_inc", "future_forward_usa_pac", "senate_leadership_fund"]
    
    for comm in committees:
        if comm not in user_data:
            feedback.append(f"Missing key: {comm} (0)")
            continue
            
        data = user_data[comm]
        comm_name_display = comm.replace('_', ' ').title()
        
        # Check ID (10 pts per committee)
        user_id = str(data.get('committee_id', '')).strip().upper()
        expected_id = EXPECTED_IDS[comm]
        
        if user_id == expected_id:
            score += 10
            feedback.append(f"{comm_name_display}: Correct ID {user_id} (+10)")
        else:
            feedback.append(f"{comm_name_display}: Incorrect ID (Got '{user_id}', expected '{expected_id}')")

        # Check Financials (10 pts per committee if plausible)
        # We perform a sanity check: Receipts > $50M, Indep Exp > $10M
        receipts = parse_money(data.get('total_receipts', 0))
        expenditures = parse_money(data.get('independent_expenditures', 0))
        
        if receipts > MIN_RECEIPTS and expenditures > MIN_EXPENDITURES:
            score += 10
            feedback.append(f"{comm_name_display}: Financials plausible (+10)")
        else:
            feedback.append(f"{comm_name_display}: Financials seem too low (Receipts: ${receipts:,.2f}, Exp: ${expenditures:,.2f})")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }