#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_switch_market_country(traj, env_info, task_info):
    """
    Verify that the agent switched JStock to the UK market and added HSBA and BP.
    
    Criteria:
    1. UK Data Directory exists (15 pts) - proves switch happened
    2. UK Data Directory created during task (15 pts) - anti-gaming
    3. Watchlist file exists in UK directory (10 pts)
    4. HSBA/HSBC in watchlist (20 pts)
    5. BP in watchlist (20 pts)
    6. VLM Verification of workflow (20 pts)
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # PROGRAMMATIC VERIFICATION (80 Points)
    # ---------------------------------------------------------
    
    # Check 1: Directory Existence (15)
    if result.get('uk_dir_exists', False):
        score += 15
        feedback_parts.append("United Kingdom market data directory created.")
    else:
        feedback_parts.append("FAIL: United Kingdom market data directory not found.")
        return {"passed": False, "score": 0, "feedback": "Did not switch country. " + " ".join(feedback_parts)}

    # Check 2: Timestamp (15)
    if result.get('uk_dir_created_during_task', False):
        score += 15
        feedback_parts.append("Directory created during task session.")
    else:
        # If directory existed before, agent didn't clear state or verification failed
        feedback_parts.append("WARN: UK directory creation timestamp mismatch (may have existed before).")
        score += 5 # Partial credit if it exists, but penalty for potential stale state

    # Check 3: Watchlist File (10)
    if result.get('watchlist_exists', False):
        score += 10
        feedback_parts.append("Watchlist file found.")
    else:
        feedback_parts.append("FAIL: No watchlist file found in UK directory.")

    # Check 4 & 5: Stocks (40)
    has_hsba = result.get('has_hsba', False)
    has_bp = result.get('has_bp', False)
    
    if has_hsba:
        score += 20
        feedback_parts.append("HSBC (HSBA) found in watchlist.")
    else:
        feedback_parts.append("FAIL: HSBC (HSBA) not found in watchlist.")

    if has_bp:
        score += 20
        feedback_parts.append("BP found in watchlist.")
    else:
        feedback_parts.append("FAIL: BP not found in watchlist.")

    # ---------------------------------------------------------
    # VLM VERIFICATION (20 Points)
    # ---------------------------------------------------------
    # We verify the visual workflow: Country menu usage -> UK Flag/Text -> Stock Entry
    
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_screen = get_final_screenshot(traj)
        
        # Build prompt for VLM
        prompt = (
            "Review these screenshots of the JStock application.\n"
            "The user should have:\n"
            "1. Opened the 'Country' menu and selected 'United Kingdom'.\n"
            "2. Added 'HSBC' (HSBA) and 'BP' to the watchlist.\n"
            "3. The final screen should show the UK watchlist with these stocks.\n\n"
            "Answer 'YES' if the workflow and final state are correct. Answer 'NO' otherwise."
        )
        
        vlm_result = query_vlm(images=frames + [final_screen], prompt=prompt)
        
        if "YES" in vlm_result.upper():
            score += 20
            feedback_parts.append("VLM: Workflow verification passed.")
        else:
            feedback_parts.append("VLM: Workflow verification failed (visuals didn't match expectations).")
            
    except Exception as e:
        logger.warning(f"VLM verification failed with error: {e}")
        # Fallback: if programmatic signals are perfect, give partial VLM points
        if score >= 80:
            score += 10
            feedback_parts.append("VLM skipped (error), added partial points based on perfect file evidence.")

    # ---------------------------------------------------------
    # FINAL SCORING
    # ---------------------------------------------------------
    # Pass threshold: 60 points (Need at least directory + one stock or directory + timestamps + watchlist)
    passed = score >= 60 and result.get('uk_dir_exists', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }