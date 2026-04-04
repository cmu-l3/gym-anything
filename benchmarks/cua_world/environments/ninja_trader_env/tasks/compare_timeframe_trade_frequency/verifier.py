#!/usr/bin/env python3
"""
Verifier for compare_timeframe_trade_frequency task.

Verifies:
1. Report file existence and creation during task.
2. Valid integer trade counts for Daily and Weekly.
3. Logical consistency: Weekly count < Daily count.
4. Data accuracy: Counts within plausible ranges for AAPL 2024 MACrossover(10,25).
5. VLM: Visual confirmation of Strategy Analyzer usage.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compare_timeframe_trade_frequency(traj, env_info, task_info):
    # 1. Setup access to container files
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Retrieve metadata
    metadata = task_info.get('metadata', {})
    daily_min = metadata.get('daily_min', 5)
    daily_max = metadata.get('daily_max', 30)
    weekly_min = metadata.get('weekly_min', 0)
    weekly_max = metadata.get('weekly_max', 10)

    # 3. Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 4. Evaluate Criteria
    score = 0
    feedback_parts = []
    
    # Criterion 1: File Existence & Anti-Gaming (20 pts)
    report_exists = result.get('report_exists', False)
    created_fresh = result.get('created_during_task', False)
    
    if report_exists and created_fresh:
        score += 20
        feedback_parts.append("Report file created (+20)")
    elif report_exists:
        score += 10
        feedback_parts.append("Report file exists but timestamp unsure (+10)")
    else:
        feedback_parts.append("Report file NOT found (0)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Data Format & Values (20 pts)
    daily_val = result.get('daily_count', -1)
    weekly_val = result.get('weekly_count', -1)
    
    valid_format = daily_val >= 0 and weekly_val >= 0
    if valid_format:
        score += 20
        feedback_parts.append(f"Valid integers found: Daily={daily_val}, Weekly={weekly_val} (+20)")
    else:
        feedback_parts.append(f"Invalid format/numbers (Daily={daily_val}, Weekly={weekly_val}) (0)")

    # Criterion 3: Logical Consistency (Weekly < Daily) (20 pts)
    if valid_format:
        if weekly_val < daily_val:
            score += 20
            feedback_parts.append("Logic correct: Weekly < Daily (+20)")
        elif weekly_val == daily_val and daily_val > 0:
             # Unlikely for this strategy/instrument
            feedback_parts.append("Suspicious: Weekly count equals Daily count (0)")
        else:
            feedback_parts.append("Logic fail: Weekly >= Daily (0)")

    # Criterion 4: Accuracy/Plausibility (20 pts)
    # Checks if values are within the broad expected ground truth ranges
    accuracy_score = 0
    if valid_format:
        if daily_min <= daily_val <= daily_max:
            accuracy_score += 10
        if weekly_min <= weekly_val <= weekly_max:
            accuracy_score += 10
    
    score += accuracy_score
    if accuracy_score == 20:
        feedback_parts.append("Values within expected ranges (+20)")
    elif accuracy_score > 0:
        feedback_parts.append("Some values out of expected range")
    else:
        feedback_parts.append("Values unreasonable for AAPL 2024")

    # Criterion 5: VLM Trajectory Verification (20 pts)
    # Ensure they actually used Strategy Analyzer
    frames = sample_trajectory_frames(traj, n=4)
    if not frames:
        feedback_parts.append("No frames for VLM check (0)")
    else:
        prompt = """
        Analyze these screenshots of NinjaTrader.
        I am looking for evidence that the user performed a Backtest in the Strategy Analyzer.
        
        Look for:
        1. A window titled "Strategy Analyzer".
        2. Settings showing "SampleMACrossover" or "Strategy".
        3. A "Results" panel or "Performance" summary showing trade statistics.
        
        Did the user open the Strategy Analyzer and run a backtest?
        Respond JSON: {"strategy_analyzer_used": bool, "confidence": float}
        """
        vlm_res = query_vlm(prompt=prompt, images=frames)
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('strategy_analyzer_used', False):
                score += 20
                feedback_parts.append("VLM confirmed Strategy Analyzer usage (+20)")
            else:
                feedback_parts.append("VLM did not see Strategy Analyzer usage (0)")
        else:
            # Fallback if VLM fails: give benefit of doubt if numbers are correct
            if accuracy_score >= 10:
                score += 20
                feedback_parts.append("VLM failed but numbers valid (+20)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }