#!/usr/bin/env python3
"""
Verifier for consolidate_watchlists task in JStock.

Criteria:
1. 'Tech' watchlist must exist.
2. 'Auto' watchlist must NOT exist.
3. 'Tech' watchlist must contain AAPL, MSFT, TSLA, F, GM.
4. 'Tech' watchlist file must have been modified during the task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_consolidate_watchlists(traj, env_info, task_info):
    """
    Verify that the agent consolidated the 'Auto' watchlist into 'Tech' and deleted 'Auto'.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define expectations
    expected_stocks = set(["AAPL", "MSFT", "TSLA", "F", "GM"])
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        
        # Check 1: Auto watchlist deleted (20 pts)
        auto_exists = result.get('auto_watchlist_exists', True)
        if not auto_exists:
            score += 20
            feedback_parts.append("Auto watchlist deleted")
        else:
            feedback_parts.append("Auto watchlist NOT deleted")

        # Check 2: Tech watchlist exists (10 pts)
        tech_exists = result.get('tech_watchlist_exists', False)
        if tech_exists:
            score += 10
            feedback_parts.append("Tech watchlist exists")
        else:
            feedback_parts.append("Tech watchlist missing")
            return {"passed": False, "score": 0, "feedback": "Tech watchlist missing"}

        # Check 3: Content Verification (60 pts total)
        # 20pts for F, 20pts for GM, 10pts for retaining original data, 10pts for deduplication
        
        # Normalize stocks from CSV to simple list of codes
        # The export script returns a list of strings
        found_stocks = result.get('tech_stocks', [])
        found_stocks_set = set([s.strip().upper() for s in found_stocks])
        
        # Check for F (Ford)
        if "F" in found_stocks_set:
            score += 20
            feedback_parts.append("Ford (F) added")
        else:
            feedback_parts.append("Ford (F) missing")
            
        # Check for GM (General Motors)
        if "GM" in found_stocks_set:
            score += 20
            feedback_parts.append("GM added")
        else:
            feedback_parts.append("GM missing")
            
        # Check for original stocks (AAPL, MSFT)
        if "AAPL" in found_stocks_set and "MSFT" in found_stocks_set:
            score += 10
            feedback_parts.append("Original stocks retained")
        else:
            feedback_parts.append("Original stocks lost")

        # Check for TSLA (should exist, but check for duplication)
        # found_stocks is a list, so we can check count
        tsla_count = sum(1 for s in found_stocks if s.strip().upper() == "TSLA")
        if tsla_count == 1:
            score += 10
            feedback_parts.append("TSLA handled correctly (no duplicates)")
        elif tsla_count > 1:
            score += 5 
            feedback_parts.append("TSLA duplicated")
        elif tsla_count == 0:
            feedback_parts.append("TSLA missing")
            
        # Check 4: Anti-gaming / Modification check (10 pts)
        modified = result.get('tech_watchlist_modified', False)
        if modified:
            score += 10
            feedback_parts.append("File modified during task")
        else:
            feedback_parts.append("File NOT modified during task")

        # Final Evaluation
        passed = score >= 80  # Requires most steps to be correct
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}