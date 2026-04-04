#!/usr/bin/env python3
"""
Verifier for enforce_follow_me_view task.

Verifies that the "Everyone follows me" moderator setting was enabled.
Verification relies on:
1. Programmatic check via JS injection (Redux store state)
2. Fallback/Confirmation via VLM trajectory analysis (Settings dialog interaction)
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# -----------------------------------------------------------------------------
# VLM Helpers
# -----------------------------------------------------------------------------

def get_final_screenshot(traj):
    """Extract the final screenshot from the trajectory."""
    if not traj or not isinstance(traj, list) or len(traj) == 0:
        return None
    last_step = traj[-1]
    if isinstance(last_step, dict):
        return last_step.get("screenshot")
    return None

def sample_trajectory_frames(traj, n=5):
    """Sample n frames uniformly from the trajectory."""
    if not traj or not isinstance(traj, list) or len(traj) == 0:
        return []
    
    # Filter for steps with screenshots
    steps_with_screens = [s for s in traj if isinstance(s, dict) and s.get("screenshot")]
    total = len(steps_with_screens)
    
    if total == 0:
        return []
    if total <= n:
        return [s["screenshot"] for s in steps_with_screens]
    
    # Sample indices
    indices = [int(i * (total - 1) / (n - 1)) for i in range(n)]
    return [steps_with_screens[i]["screenshot"] for i in indices]

def query_vlm_wrapper(vlm_func, prompt, images):
    """Safe wrapper for VLM query."""
    if not vlm_func or not images:
        return {"success": False, "error": "No VLM or images"}
    try:
        return vlm_func(prompt=prompt, images=images)
    except Exception as e:
        return {"success": False, "error": str(e)}

# -----------------------------------------------------------------------------
# Verifier
# -----------------------------------------------------------------------------

def verify_enforce_follow_me_view(traj, env_info, task_info):
    """
    Verify that the 'Everyone follows me' setting is enabled.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm') # Might be available depending on framework version
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 1. Load programmatic result
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        # Continue to VLM fallback if possible, but penalize
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    passed = False

    # -------------------------------------------------------------------------
    # Criterion 1: Programmatic Check (Primary) - 60 points
    # -------------------------------------------------------------------------
    js_verified = result.get("follow_me_enabled", False)
    app_running = result.get("app_was_running", False)

    if app_running:
        score += 10
        feedback_parts.append("App verified running")
    else:
        feedback_parts.append("App was not running at end")

    if js_verified:
        score += 50
        feedback_parts.append("Configuration verified via internal state")
    else:
        feedback_parts.append("Configuration NOT detected in internal state")

    # -------------------------------------------------------------------------
    # Criterion 2: VLM Trajectory Verification (Secondary) - 40 points
    # -------------------------------------------------------------------------
    # We look for evidence that the user opened Settings and clicked "Everyone follows me"
    
    vlm_score = 0
    vlm_passed = False
    
    # We need the VLM function provided by the framework usually, 
    # but here we'll assume it's passed or imported. 
    # If standard gym_anything imports are available:
    try:
        from gym_anything.vlm import query_vlm as standard_query_vlm
        query_vlm = query_vlm or standard_query_vlm
    except ImportError:
        pass

    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        final_screen = get_final_screenshot(traj)
        if final_screen:
            frames.append(final_screen)
            
        if frames:
            prompt = """
            You are verifying a Jitsi Meet task. The user must enable the "Everyone follows me" setting.
            
            Look at the sequence of screenshots.
            1. Did the user open a "Settings" dialog? (Usually a modal window in the center).
            2. Did they navigate to a "More" or "Moderator" tab?
            3. Is the "Everyone follows me" checkbox visible and checked/toggled ON?
            
            Return JSON:
            {
                "settings_opened": boolean,
                "moderator_options_seen": boolean,
                "follow_me_checked": boolean,
                "confidence": "low"|"medium"|"high"
            }
            """
            
            vlm_res = query_vlm_wrapper(query_vlm, prompt, frames)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                
                if parsed.get("settings_opened"):
                    vlm_score += 10
                    feedback_parts.append("Settings dialog detected")
                
                if parsed.get("follow_me_checked"):
                    vlm_score += 30
                    feedback_parts.append("Visual evidence of 'Follow Me' enabled")
                    vlm_passed = True
                elif parsed.get("moderator_options_seen"):
                    vlm_score += 10
                    feedback_parts.append("Moderator options seen but toggle not clearly confirmed")

    score += vlm_score

    # -------------------------------------------------------------------------
    # Final Scoring
    # -------------------------------------------------------------------------
    
    # Pass if JS verification succeeded OR strong VLM evidence found
    passed = (js_verified) or (vlm_passed and score >= 60)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }