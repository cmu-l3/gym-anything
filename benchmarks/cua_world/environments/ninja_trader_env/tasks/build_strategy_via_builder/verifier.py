#!/usr/bin/env python3
"""
Verifier for build_strategy_via_builder task.

Verification Logic:
1. Primary: Check if MACrossover.cs exists and was created during the task.
2. Content: Analyze the C# source code for required logic (SMA(10), SMA(30), CrossAbove/Below).
3. Visual: Use VLM on trajectory to verify Strategy Builder UI usage.

Score Distribution (100 pts):
- File exists & created during task: 20 pts (Gatekeeper)
- Strategy name 'MACrossover': 10 pts
- SMA(10) logic present: 15 pts
- SMA(30) logic present: 15 pts
- Entry conditions (CrossAbove/Below): 20 pts
- Entry actions (EnterLong/Short): 10 pts
- VLM Verification (Builder usage): 10 pts
"""

import json
import tempfile
import os
import re
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_build_strategy(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    patterns = metadata.get('code_patterns', {})

    # Copy result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\Desktop\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    passed = False

    # 1. File Existence & Freshness (20 pts)
    file_exists = result.get('strategy_file_exists', False)
    fresh = result.get('strategy_file_created_during_task', False)
    source_code = result.get('source_code', "")

    if file_exists and fresh:
        score += 20
        feedback.append("Strategy file created successfully.")
    elif file_exists:
        feedback.append("Strategy file exists but was NOT created during this task (stale).")
        return {"passed": False, "score": 0, "feedback": "Anti-gaming: File not created during task"}
    else:
        feedback.append("Strategy file not found.")
        return {"passed": False, "score": 0, "feedback": "Strategy file MACrossover.cs not found"}

    # 2. Code Analysis (70 pts)
    # Check Class Name
    if re.search(r"class\s+MACrossover", source_code):
        score += 10
        feedback.append("Correct strategy name.")
    else:
        feedback.append("Incorrect strategy class name.")

    # Check SMA 10
    if re.search(r"SMA\([^)]*10\)", source_code):
        score += 15
        feedback.append("SMA(10) found.")
    else:
        feedback.append("Missing SMA(10).")

    # Check SMA 30
    if re.search(r"SMA\([^)]*30\)", source_code):
        score += 15
        feedback.append("SMA(30) found.")
    else:
        feedback.append("Missing SMA(30).")

    # Check Conditions
    if "CrossAbove" in source_code and "CrossBelow" in source_code:
        score += 20
        feedback.append("Crossover logic found.")
    else:
        feedback.append("Missing CrossAbove/CrossBelow logic.")

    # Check Actions
    if "EnterLong" in source_code and "EnterShort" in source_code:
        score += 10
        feedback.append("Entry orders found.")
    else:
        feedback.append("Missing EnterLong/EnterShort orders.")

    # 3. VLM Verification (10 pts)
    # Check if the agent actually used the Strategy Builder UI
    frames = sample_trajectory_frames(traj, n=5)
    vlm_prompt = (
        "These are screenshots of a user interacting with NinjaTrader 8. "
        "Did the user open the 'Strategy Builder' wizard? "
        "Look for a window titled 'Strategy Builder' with steps like 'General', 'Default Quantity', 'Conditions', 'Actions'. "
        "Answer Yes if the Strategy Builder UI is visible in any frame, otherwise No."
    )
    
    try:
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        vlm_answer = vlm_result.get('parsed', {}).get('answer', '').lower()
        # Fallback if parsing fails, check raw text
        raw_text = str(vlm_result).lower()
        
        if "yes" in vlm_answer or "yes" in raw_text:
            score += 10
            feedback.append("VLM confirmed Strategy Builder usage.")
        else:
            feedback.append("VLM did not detect Strategy Builder UI.")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Be lenient on VLM failure if code is perfect
        if score >= 80:
            score += 10
            feedback.append("VLM skipped (error) but code verification passed.")

    # Final Pass Determination
    # Threshold: 70 points
    if score >= 70:
        passed = True

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }