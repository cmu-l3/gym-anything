#!/usr/bin/env python3
"""
Verifier for delete_portfolio task in JStock.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_delete_portfolio(traj, env_info, task_info):
    """
    Verify that the 'Speculative Trades' portfolio was deleted and 'My Portfolio' preserved.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    target_exists = result.get('target_exists', True)  # Should be False
    preserved_exists = result.get('preserved_exists', False) # Should be True
    preserved_integrity = result.get('preserved_integrity', False) # Should be True
    fs_modified = result.get('filesystem_modified_during_task', False)
    final_count = result.get('final_portfolio_count', 0)
    initial_count = result.get('initial_portfolio_count', 0)

    # Criterion 1: Target Portfolio Deleted (30 pts)
    if not target_exists:
        score += 30
        feedback_parts.append("Target portfolio 'Speculative Trades' successfully deleted.")
    else:
        feedback_parts.append("Target portfolio 'Speculative Trades' still exists.")

    # Criterion 2: Preserved Portfolio Exists (20 pts)
    if preserved_exists:
        score += 20
        feedback_parts.append("'My Portfolio' still exists.")
    else:
        feedback_parts.append("CRITICAL: 'My Portfolio' was deleted!")

    # Criterion 3: Preserved Portfolio Integrity (20 pts)
    if preserved_integrity:
        score += 20
        feedback_parts.append("'My Portfolio' content (AAPL, MSFT, NVDA) is intact.")
    else:
        if preserved_exists:
            feedback_parts.append("'My Portfolio' exists but data is corrupted/missing.")
        else:
            feedback_parts.append("Cannot verify integrity because 'My Portfolio' is missing.")

    # Criterion 4: Directory Count Check (10 pts)
    # Should contain only 1 directory (My Portfolio)
    if final_count == 1:
        score += 10
        feedback_parts.append("Portfolio count is correct (1).")
    else:
        feedback_parts.append(f"Portfolio count incorrect (Expected 1, got {final_count}).")

    # Criterion 5: Anti-Gaming / Real Action (20 pts)
    # Verify file system was actually modified during task window
    if fs_modified:
        score += 20
        feedback_parts.append("Filesystem modification detected during task.")
    else:
        feedback_parts.append("No filesystem modification timestamp detected during task.")
        if not target_exists and final_count == 1:
             feedback_parts.append("(Warning: Portfolio might have been deleted too quickly or timestamp granularity issue)")
             # Fallback: if state is perfect, give benefit of doubt for timestamp
             score += 20

    # Success Logic
    # Must have deleted target AND kept preserved AND integrity good
    passed = (not target_exists) and preserved_exists and preserved_integrity and (score >= 60)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }