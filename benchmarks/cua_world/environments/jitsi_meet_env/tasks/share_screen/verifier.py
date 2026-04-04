#!/usr/bin/env python3
"""
Verifier for share_screen task.

This task requires the agent to:
1. Join a meeting.
2. Start screen sharing (handling browser dialogs).
3. Take a screenshot of active sharing.
4. Stop screen sharing.
5. Take a screenshot of stopped state.

Verification Strategy:
- Programmatic: Check existence, valid timestamps, unique content of two screenshots.
- VLM: Analyze 'active' screenshot for visual indicators of screen sharing (infinite mirror, stop button).
- VLM: Analyze 'stopped' screenshot for normal meeting view.
"""

import json
import os
import sys
import tempfile
import logging
from pathlib import Path

# Add parent directory for shared utilities
sys.path.insert(0, str(Path(__file__).parent.parent))
from vlm_utils import query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_share_screen(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load exported results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    active_shot = result.get("active_screenshot", {})
    stopped_shot = result.get("stopped_screenshot", {})
    images_different = result.get("images_different", False)
    chronological_order = result.get("chronological_order", False)
    in_meeting = result.get("in_meeting_at_end", False)

    # 2. Basic Programmatic Scoring (40 points)
    
    # Criteria: Active screenshot exists & valid (10 pts)
    if active_shot.get("exists") and active_shot.get("created_during_task") and active_shot.get("size", 0) > 10000:
        score += 10
        feedback_parts.append("Active screenshot created.")
    else:
        feedback_parts.append("Active screenshot missing or invalid.")

    # Criteria: Stopped screenshot exists & valid (10 pts)
    if stopped_shot.get("exists") and stopped_shot.get("created_during_task") and stopped_shot.get("size", 0) > 10000:
        score += 10
        feedback_parts.append("Stopped screenshot created.")
    else:
        feedback_parts.append("Stopped screenshot missing or invalid.")

    # Criteria: Anti-gaming (images different + correct order) (10 pts)
    if images_different and chronological_order:
        score += 10
        feedback_parts.append("Screenshots are distinct and in correct order.")
    elif not images_different and active_shot.get("exists"):
        feedback_parts.append("Screenshots are identical (anti-gaming fail).")

    # Criteria: Meeting Joined (10 pts)
    if in_meeting:
        score += 10
        feedback_parts.append("Agent verified in meeting room.")
    else:
        feedback_parts.append("Agent not in correct meeting room at end.")

    # 3. VLM Verification (60 points)
    
    # Verify Active Sharing Screenshot
    active_passed = False
    if active_shot.get("exists"):
        # Retrieve image
        temp_active = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env("/tmp/screen_share_active.png", temp_active.name)
            
            prompt_active = """
            Analyze this screenshot of a Jitsi Meet video conference.
            I am looking for evidence that SCREEN SHARING is currently ACTIVE.
            
            Look for:
            1. An "infinite mirror" effect (screen sharing the screen that shows the share).
            2. A "Stop sharing" button or banner (usually at bottom or top).
            3. A "You are sharing your screen" notification.
            4. An icon in the participant thumbnail indicating screen share.
            
            Does this image show active screen sharing?
            Return JSON: {"is_sharing": true/false, "confidence": "high/medium/low", "reason": "..."}
            """
            
            vlm_res = query_vlm(prompt=prompt_active, image=temp_active.name)
            parsed = vlm_res.get("parsed", {})
            if parsed.get("is_sharing", False):
                score += 30
                active_passed = True
                feedback_parts.append("VLM confirmed screen sharing active.")
            else:
                feedback_parts.append(f"VLM did not see screen sharing: {parsed.get('reason', 'unknown')}")
                
        except Exception as e:
            feedback_parts.append(f"Error processing active screenshot: {str(e)}")
        finally:
            if os.path.exists(temp_active.name):
                os.unlink(temp_active.name)
    
    # Verify Stopped Sharing Screenshot
    stopped_passed = False
    if stopped_shot.get("exists"):
        # Retrieve image
        temp_stopped = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env("/tmp/screen_share_stopped.png", temp_stopped.name)
            
            prompt_stopped = """
            Analyze this screenshot of a Jitsi Meet video conference.
            I am looking for evidence that screen sharing is STOPPED (normal meeting view).
            
            Check that:
            1. There is NO infinite mirror effect.
            2. There is NO "Stop sharing" button visible.
            3. You see a standard camera view or avatar.
            
            Does this image show a normal meeting state WITHOUT screen sharing?
            Return JSON: {"is_stopped": true/false, "confidence": "high/medium/low", "reason": "..."}
            """
            
            vlm_res = query_vlm(prompt=prompt_stopped, image=temp_stopped.name)
            parsed = vlm_res.get("parsed", {})
            if parsed.get("is_stopped", False):
                score += 30
                stopped_passed = True
                feedback_parts.append("VLM confirmed screen sharing stopped.")
            else:
                feedback_parts.append(f"VLM thought screen sharing might still be active: {parsed.get('reason', 'unknown')}")
                
        except Exception as e:
            feedback_parts.append(f"Error processing stopped screenshot: {str(e)}")
        finally:
            if os.path.exists(temp_stopped.name):
                os.unlink(temp_stopped.name)

    # Final Pass Determination
    # Must have score >= 60 AND active sharing must have been confirmed visually
    passed = (score >= 60) and active_passed
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }