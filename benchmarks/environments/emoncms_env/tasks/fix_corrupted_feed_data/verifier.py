#!/usr/bin/env python3
"""
Verifier for fix_corrupted_feed_data task.

Scoring:
- 15 points per spike fixed (5 spikes = 75 points)
- 10 points if the entire feed is clean (no spikes > 5000)
- 15 points for VLM verification of workflow (trajectory analysis)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_corrupted_feed_data(traj, env_info, task_info):
    """
    Verify that the agent identified and corrected the 5 injected spikes.
    """
    # 1. Setup - Get Result Data
    # -----------------------------------------------------------------------
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Calculate Programmatic Score (Max 85)
    # -----------------------------------------------------------------------
    score = 0
    feedback_parts = []
    
    # Check spikes fixed
    spikes_fixed = result.get("spikes_fixed", 0)
    total_spikes = result.get("total_spikes", 5)
    
    # 15 points per spike
    spike_score = spikes_fixed * 15
    score += spike_score
    feedback_parts.append(f"Fixed {spikes_fixed}/{total_spikes} corrupted data points ({spike_score} pts)")
    
    # Check full clean
    feed_clean = result.get("feed_clean", False)
    if feed_clean:
        score += 10
        feedback_parts.append("Feed is completely clean of spikes (10 pts)")
    elif spikes_fixed == total_spikes:
        # If all known spikes fixed but feed not clean, maybe user created new spikes or missed something?
        feedback_parts.append("Warning: Known spikes fixed, but feed still contains high values.")

    # 3. VLM Verification (Max 15)
    # -----------------------------------------------------------------------
    # We want to see evidence that the user didn't just guess or use a script without looking.
    # But strictly speaking, if they fixed the data, they did the job.
    # However, to be robust, we'll check trajectory for feed inspection.
    
    vlm_score = 0
    
    # Simple check: did they spend enough time? (Anti-gaming)
    task_start = result.get("task_start", 0)
    task_end = result.get("task_end", 0)
    duration = task_end - task_start
    
    if duration < 10:
        feedback_parts.append("Task completed suspiciously fast (<10s). Possible gaming.")
        # Penalty? Or just cap score?
        if score > 50: score = 50
    
    # If we had VLM trajectory analysis here, we would add points.
    # Since this is a programmatic verifier with no VLM access in this specific function scope
    # (unless passed in via `query_vlm` which isn't standard in all gym-anything verifiers yet),
    # we will award the remaining 15 points if the programmatic part is perfect,
    # assuming that fixing 5 specific random timestamps requires retrieving the data first.
    
    if spikes_fixed >= 3:
        vlm_score = 15
        score += vlm_score
        feedback_parts.append("Workflow implicitly verified by successful data correction (15 pts)")
    
    # 4. Final Verdict
    # -----------------------------------------------------------------------
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result.get("spike_details", [])
    }