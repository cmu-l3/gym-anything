#!/usr/bin/env python3
"""
Verifier for Configure Level II Depth Window task (NinjaTrader 8).

Verifies that:
1. The workspace was saved (modified after task start).
2. A Level II window exists in the saved workspace.
3. The instrument is set to SPY.
4. The 'Show Order Entry' property is enabled.

Score Distribution:
- Workspace Saved: 20 pts
- Level II Window Exists: 30 pts
- Correct Instrument (SPY): 20 pts
- Order Entry Enabled: 30 pts

Pass Threshold: 70 pts
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Path inside the container (Windows) where the result JSON is saved
CONTAINER_RESULT_PATH = "C:/Users/Docker/Desktop/NinjaTraderTasks/configure_level_ii_depth_window_result.json"

def verify_configure_level_ii_depth_window(traj, env_info, task_info):
    """
    Verify the Level II window configuration task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification failed: copy_from_env not available"}

    # Temporary file to store the copied result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_path = temp_file.name
    temp_file.close()

    try:
        # Copy result from container to host
        copy_from_env(CONTAINER_RESULT_PATH, temp_path)
        
        if not os.path.exists(temp_path) or os.path.getsize(temp_path) == 0:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Result file extraction failed or file is empty."
            }

        with open(temp_path, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
            
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Error reading verification data: {str(e)}"
        }
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    # Calculate Score
    score = 0
    feedback_parts = []

    # Criterion 1: Workspace Saved (20 pts)
    # This prevents "do nothing" agents
    if result.get("workspace_modified", False):
        score += 20
        feedback_parts.append("Workspace saved (+20)")
    else:
        feedback_parts.append("Workspace NOT saved (0)")

    # Criterion 2: Level II Window Exists (30 pts)
    if result.get("has_level_ii", False):
        score += 30
        feedback_parts.append("Level II window found (+30)")
    else:
        feedback_parts.append("Level II window NOT found (0)")

    # Criterion 3: Correct Instrument (20 pts)
    if result.get("correct_instrument", False):
        score += 20
        feedback_parts.append("Instrument SPY correct (+20)")
    else:
        feedback_parts.append("Instrument SPY NOT found in Level II window (0)")

    # Criterion 4: Order Entry Enabled (30 pts)
    if result.get("order_entry_enabled", False):
        score += 30
        feedback_parts.append("Order Entry enabled (+30)")
    else:
        feedback_parts.append("Order Entry NOT enabled (0)")

    # Final Evaluation
    # Threshold 70 means they must at least have saved, created the window, and set instrument (70)
    # OR saved, created window, and enabled order entry (80)
    # Essentially, creating the window correctly is the main goal.
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }