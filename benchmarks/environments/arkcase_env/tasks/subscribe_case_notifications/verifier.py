#!/usr/bin/env python3
"""
Verifier for subscribe_case_notifications task.

Strategies:
1. API Verification (Primary): Check if the user is subscribed to the case ID.
2. VLM Verification (Secondary): Check screenshots for visual indicators (Star/Bell/Unsubscribe).
"""

import json
import tempfile
import os
import logging
import sys

# Add parent directory to path to import vlm_utils if needed, 
# though we use gym_anything.vlm patterns typically provided in the environment
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_subscribe_case_notifications(traj, env_info, task_info):
    """
    Verify the agent subscribed to the complaint case.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    
    # --- Criterion 1: API Confirmation (50 points) ---
    is_subscribed = result.get('is_subscribed', False)
    case_id = result.get('case_id', 'Unknown')
    
    if is_subscribed:
        score += 50
        feedback_parts.append("✅ API confirms subscription is active")
    else:
        feedback_parts.append("❌ API does not show active subscription")

    # --- Criterion 2: App was running (10 points) ---
    if result.get('app_running', False):
        score += 10
    else:
        feedback_parts.append("⚠️ Browser not running at end of task")

    # --- Criterion 3: Visual Verification (40 points) ---
    # We look for "Unsubscribe", "Following", a filled star/bell, or the specific case title
    
    frames = sample_trajectory_frames(traj, n=3)
    final_img = get_final_screenshot(traj)
    images_to_check = frames + [final_img] if final_img else frames
    
    if not images_to_check:
        feedback_parts.append("❌ No screenshots available for visual verification")
    else:
        # Construct VLM prompt
        prompt = f"""
        You are verifying an ArkCase task. The goal was to subscribe to/follow a case titled 'Improper Records Retention Complaint'.
        
        Look at these screenshots (chronological order) and determine:
        1. Did the user navigate to a case titled 'Improper Records Retention Complaint'?
        2. Did the user click a 'Subscribe', 'Follow', 'Watch' button or a Bell/Star icon?
        3. Is there any visual indication that the user is now subscribed (e.g., button says 'Unsubscribe', 'Following', or icon is filled/highlighted)?
        
        Return JSON:
        {{
            "case_seen": true/false,
            "subscribe_action_observed": true/false,
            "subscription_confirmed_visually": true/false,
            "reasoning": "..."
        }}
        """
        
        try:
            vlm_res = query_vlm(
                prompt=prompt,
                images=images_to_check,
                model="gpt-4o" # or default
            )
            
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('case_seen', False):
                score += 10
                feedback_parts.append("✅ VLM: Case navigation observed")
            
            if parsed.get('subscribe_action_observed', False) or parsed.get('subscription_confirmed_visually', False):
                score += 30
                feedback_parts.append("✅ VLM: Subscribe action/state observed")
            else:
                feedback_parts.append("❌ VLM: Could not visually confirm subscription action")
                
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            feedback_parts.append("⚠️ VLM verification error")
            # Fallback points if API passed
            if is_subscribed:
                score += 20 # Give benefit of doubt if API worked but VLM failed

    # Final Score Calculation
    passed = score >= 60 and is_subscribed
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }