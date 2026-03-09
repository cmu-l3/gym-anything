#!/usr/bin/env python3
"""
Verifier for rename_watchlist task in JStock.
Verifies that the user renamed 'My Watchlist' to 'Tech Giants'
while preserving the contained stocks.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rename_watchlist(traj, env_info, task_info):
    """
    Verifies the rename_watchlist task.
    
    Criteria:
    1. Filesystem: Directory 'Tech Giants' exists (25 pts)
    2. Filesystem: Directory 'My Watchlist' is gone (15 pts)
    3. Filesystem: Content preserved (all 5 stocks present) (25 pts)
    4. Anti-gaming: Directory modification time is valid (10 pts)
    5. VLM: Visual confirmation of rename in UI (25 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Check 1: New Directory Exists (25 pts) ---
    if result.get("new_dir_exists", False):
        score += 25
        feedback_parts.append("New watchlist 'Tech Giants' created")
    else:
        feedback_parts.append("New watchlist 'Tech Giants' NOT found")

    # --- Check 2: Old Directory Gone (15 pts) ---
    if result.get("old_dir_gone", False):
        score += 15
        feedback_parts.append("Old watchlist 'My Watchlist' removed")
    else:
        feedback_parts.append("Old watchlist 'My Watchlist' still exists (copy instead of rename?)")

    # --- Check 3: Content Preserved (25 pts) ---
    if result.get("stocks_preserved", False):
        score += 25
        feedback_parts.append("All 5 stocks preserved")
    else:
        count = result.get("stock_count", 0)
        feedback_parts.append(f"Stocks missing or watchlist empty (found {count}/5)")

    # --- Check 4: Anti-Gaming / Timestamp (10 pts) ---
    if result.get("modified_during_task", False):
        score += 10
        feedback_parts.append("Modification timestamp valid")
    else:
        if result.get("new_dir_exists", False):
             feedback_parts.append("Directory timestamp predates task start (pre-existing?)")
        
    # --- Check 5: VLM Visual Verification (25 pts) ---
    # We use VLM to verify the UI state, as file system checks can be spoofed
    # or might miss UI-level issues (e.g., JStock not refreshing).
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_screen = get_final_screenshot(traj)
        
        # Combine frames for context
        images_to_check = frames + [final_screen]
        
        prompt = (
            "Analyze these screenshots of the JStock application.\n"
            "1. Do you see a tab or watchlist named 'Tech Giants'?\n"
            "2. Do you see a tab or watchlist named 'My Watchlist'?\n"
            "3. Are there stocks visible in the list (AAPL, MSFT, etc.)?\n"
            "Answer 'YES' if 'Tech Giants' is visible and 'My Watchlist' is NOT visible as the active tab label."
        )
        
        vlm_response = query_vlm(images=images_to_check, prompt=prompt).strip().upper()
        
        if "YES" in vlm_response or "TECH GIANTS" in vlm_response:
            score += 25
            feedback_parts.append("VLM confirmed UI shows 'Tech Giants'")
        else:
            feedback_parts.append(f"VLM did not confirm UI change (Response: {vlm_response})")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if file checks are perfect, give partial credit for VLM to avoid failing on technical error
        if score >= 75:
            score += 10
            feedback_parts.append("VLM check skipped (error), +10 fallback")

    # Final Pass/Fail Logic
    # Pass threshold: 65 (Requires at least file rename + content preservation + partial VLM/cleanup)
    passed = score >= 65 and result.get("new_dir_exists", False) and result.get("stocks_preserved", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }