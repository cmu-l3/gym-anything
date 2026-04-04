#!/usr/bin/env python3
"""
Verifier for remove_stocks_from_watchlist task.

Verifies:
1. File-based: GOOGL and AMZN are removed from CSV.
2. File-based: AAPL, MSFT, NVDA are retained in CSV.
3. Anti-gaming: File was actually modified during task.
4. VLM: Trajectory shows interaction with JStock UI.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_remove_stocks(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    stocks_to_remove = set(metadata.get('stocks_to_remove', ["GOOGL", "AMZN"]))
    stocks_to_retain = set(metadata.get('stocks_to_retain', ["AAPL", "MSFT", "NVDA"]))
    
    # Retrieve result JSON
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
    
    # ------------------------------------------------------------
    # 1. Programmatic Verification (CSV Content) - 70 points
    # ------------------------------------------------------------
    
    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Watchlist file deleted or not found"}

    current_stocks = set(result.get("stock_list", []))
    
    # Check Removed Stocks (20 pts each)
    removed_count = 0
    for stock in stocks_to_remove:
        if stock not in current_stocks:
            score += 20
            removed_count += 1
            feedback_parts.append(f"Successfully removed {stock}")
        else:
            feedback_parts.append(f"Failed to remove {stock}")

    # Check Retained Stocks (10 pts each)
    retained_count = 0
    for stock in stocks_to_retain:
        if stock in current_stocks:
            score += 10
            retained_count += 1
        else:
            feedback_parts.append(f"Accidentally removed {stock}")
    
    if retained_count == len(stocks_to_retain):
        feedback_parts.append(f"All {retained_count} other stocks retained")

    # Anti-gaming check (File modification)
    if result.get("file_content_changed", False) and result.get("file_modified_during_task", False):
        score += 5  # Bonus for clean modification
    elif not result.get("file_content_changed", False):
        feedback_parts.append("Warning: Watchlist file identical to initial state (no changes saved)")
        # If file didn't change, they likely failed removal checks anyway, but we ensure fail here
        if score > 0:
            score = 0 
            feedback_parts.append("FAIL: No changes detected in watchlist file")

    # ------------------------------------------------------------
    # 2. VLM Verification (Trajectory) - 25 points
    # ------------------------------------------------------------
    # We verify the agent actually used the UI to delete stocks
    
    try:
        frames = sample_trajectory_frames(traj, n=5)
        final_screen = get_final_screenshot(traj)
        
        vlm_prompt = (
            "Analyze these screenshots of a stock market application (JStock). "
            "The goal was to remove specific stocks from a list. "
            "1. Do you see a table listing stocks like AAPL, MSFT, GOOGL? "
            "2. Does the user select rows and delete them (using menu or keyboard)? "
            "3. In the final state, are GOOGL and AMZN gone, while AAPL/MSFT remain? "
            "Answer 'YES' if the workflow appears correct."
        )
        
        vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt).strip().upper()
        
        if "YES" in vlm_result:
            score += 25
            feedback_parts.append("VLM verification passed (UI workflow confirmed)")
        else:
            feedback_parts.append("VLM verification warning: UI workflow unclear")
            # We don't penalize heavily if programmatic passed, but we add points if it confirms
            
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        feedback_parts.append("VLM verification skipped due to error")
        # Grant partial points if programmatic is perfect to avoid failing on infra error
        if score >= 70:
            score += 25

    # ------------------------------------------------------------
    # Final Scoring
    # ------------------------------------------------------------
    # Max score: 40 (removal) + 30 (retention) + 5 (modification) + 25 (VLM) = 100
    
    passed = (score >= 60) and (removed_count == len(stocks_to_remove))
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }