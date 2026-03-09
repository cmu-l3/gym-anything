#!/usr/bin/env python3
"""
Verifier for share_youtube_video task.

Criteria:
1. Meeting Active (Programmatic): 10 pts
2. Agent did something (Screenshot Changed): 10 pts
3. Trajectory Workflow (VLM): 30 pts (Menu access -> Dialog -> Input)
4. Video Visible (VLM): 50 pts (Final screenshot shows embedded player)

Pass Threshold: 60/100
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Mock imports for environment where gym_anything is not available during generation
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Stub functions for standalone testing
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(images, prompt): return {"success": False, "error": "VLM stub"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_share_youtube_video(traj, env_info, task_info):
    """
    Verify the YouTube video sharing task using programmatic state and VLM analysis.
    """
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # Load task result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # Programmatic Checks (20 points)
    # ------------------------------------------------------------------
    
    # Check 1: Meeting Active (10 pts)
    if result.get("meeting_active", False):
        score += 10
        feedback_parts.append("Meeting is active (+10)")
    else:
        feedback_parts.append("Meeting is NOT active")

    # Check 2: Screenshot Changed (10 pts) - Anti-gaming "do nothing" check
    if result.get("screenshot_changed", False):
        score += 10
        feedback_parts.append("UI state changed (+10)")
    else:
        feedback_parts.append("No UI change detected (Did you perform the task?)")

    # ------------------------------------------------------------------
    # VLM Verification (80 points)
    # ------------------------------------------------------------------
    
    # Prepare images
    traj_frames = sample_trajectory_frames(traj, n=6)
    final_screen = get_final_screenshot(traj)
    
    # If we have no images, we can't verify further
    if not traj_frames and not final_screen:
        return {
            "passed": False, 
            "score": score, 
            "feedback": "No video evidence available for verification. " + "; ".join(feedback_parts)
        }

    # VLM Check 1: Workflow Trajectory (30 pts)
    # Did the agent open menus and dialogs?
    workflow_prompt = """
    Analyze these screenshots of a Jitsi Meet session.
    Look for the following steps:
    1. Clicking the 'More actions' (three dots) menu in the toolbar.
    2. A menu appearing with options like 'Share video', 'Settings', etc.
    3. A 'Share video' dialog appearing with a URL input field.
    4. A YouTube URL being entered.

    Did the agent perform these actions?
    Respond JSON: {"steps_completed": ["list"], "workflow_valid": true/false}
    """
    
    workflow_result = query_vlm(images=traj_frames, prompt=workflow_prompt)
    workflow_score = 0
    
    if workflow_result.get("success"):
        parsed = workflow_result.get("parsed", {})
        if parsed.get("workflow_valid", False) or len(parsed.get("steps_completed", [])) >= 2:
            workflow_score = 30
            feedback_parts.append("Workflow verification passed (+30)")
        elif len(parsed.get("steps_completed", [])) > 0:
            workflow_score = 15
            feedback_parts.append("Partial workflow detected (+15)")
    
    score += workflow_score

    # VLM Check 2: Final Result (50 pts)
    # Is the video actually visible?
    final_prompt = """
    Look at this final screenshot of the meeting.
    Is there a YouTube video player embedded in the meeting interface?
    It should look like a large video frame, possibly showing 'Big Buck Bunny' or a YouTube play button/interface, distinct from a regular webcam view.
    
    Respond JSON: {"video_player_visible": true/false, "confidence": "high/medium/low"}
    """
    
    # Use final screenshot from trajectory or result file if needed
    # Ideally use the one from trajectory which is trusted
    vis_result = query_vlm(images=[final_screen], prompt=final_prompt)
    vis_score = 0
    
    if vis_result.get("success"):
        parsed = vis_result.get("parsed", {})
        if parsed.get("video_player_visible", False):
            vis_score = 50
            feedback_parts.append("YouTube video player visible (+50)")
        else:
            feedback_parts.append("No YouTube player detected in final view")
            
    score += vis_score

    # ------------------------------------------------------------------
    # Final Decision
    # ------------------------------------------------------------------
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }