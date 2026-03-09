#!/usr/bin/env python3
"""
Verifier for GCompris Canal Lock Activity.

Verification Strategy:
1. File Check (20 pts): 'canal_lock_complete.png' exists and created during task.
2. App State (5 pts): GCompris is running.
3. VLM Trajectory Verification (75 pts):
   - Found activity (20 pts)
   - Scene visible (15 pts)
   - Interaction w/ gates/water (20 pts)
   - Level completed (20 pts)
"""

import json
import os
import tempfile
import logging
import sys
from pathlib import Path

# Add parent directory to path to import vlm_utils if available
sys.path.insert(0, str(Path(__file__).parent.parent))

try:
    from vlm_utils import query_vlm, sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback if vlm_utils not found in environment
    def sample_trajectory_frames(traj, n=5):
        return traj[::max(1, len(traj)//n)] if traj else []
    
    def get_final_screenshot(traj):
        return traj[-1] if traj else None
        
    def query_vlm(**kwargs):
        print("WARNING: VLM client not available, returning dummy success")
        return {"success": True, "parsed": {"workflow_score": 75}}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """
You are analyzing a screen recording of a user performing an educational task in GCompris: "Operate a Canal Lock".
The user must:
1. Navigate to the Canal Lock activity.
2. Open the activity (showing a boat, canal, gates, valves).
3. Operate the controls (click gates/valves) to move the boat.
4. Successfully guide the boat through the lock.

Review the sequence of screenshots provided.
Determine which of the following milestones were achieved:

1. ACTIVITY_FOUND: Did the user find and click the "Canal Lock" activity? (Look for navigation from menu to the specific activity).
2. SCENE_VISIBLE: Is the canal lock simulation visible? (Water, boat, brick walls, control buttons).
3. INTERACTION: Is there evidence of interacting with the lock? (Gates opening/closing, water level rising/falling, boat moving).
4. COMPLETED: Did the boat successfully exit the lock or is there a "Great/Star" success animation?
5. SCREENSHOT_MATCH: Does the LAST image look like the user took a screenshot of the completed state?

Return a JSON object:
{
  "activity_found": true/false,
  "scene_visible": true/false,
  "interaction_evident": true/false,
  "level_completed": true/false,
  "screenshot_match": true/false,
  "reasoning": "brief explanation"
}
"""

def verify_canal_lock_activity(traj, env_info, task_info):
    """
    Verify the Canal Lock activity task using file checks and VLM trajectory analysis.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load programmatic results from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criterion 1: Screenshot File (20 pts)
    if result.get('screenshot_exists') and result.get('screenshot_valid_timestamp'):
        if result.get('screenshot_size_bytes', 0) > 5000: # Min 5KB
            score += 20
            feedback.append("Screenshot saved correctly (+20)")
        else:
            score += 10
            feedback.append("Screenshot file exists but is very small (+10)")
    else:
        feedback.append("Screenshot not saved or timestamp invalid (0)")

    # Criterion 2: App Running (5 pts)
    if result.get('app_running'):
        score += 5
        feedback.append("GCompris is running (+5)")

    # Criterion 3: VLM Trajectory Verification (75 pts max)
    # Sample frames from trajectory
    frames = sample_trajectory_frames(traj, n=6)
    
    # We also check the saved screenshot if available in traj (usually it's just screen frames)
    # We will rely on trajectory frames to prove work.
    
    if not frames:
        return {"passed": False, "score": score, "feedback": "No trajectory frames available for verification"}

    vlm_result = query_vlm(prompt=VLM_PROMPT, images=frames)
    
    vlm_score = 0
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("activity_found"):
            vlm_score += 20
            feedback.append("Activity found (+20)")
        
        if parsed.get("scene_visible"):
            vlm_score += 15
            feedback.append("Canal lock scene visible (+15)")
            
        if parsed.get("interaction_evident"):
            vlm_score += 20
            feedback.append("Interaction with controls detected (+20)")
            
        if parsed.get("level_completed"):
            vlm_score += 20
            feedback.append("Level completion detected (+20)")
            
        score += vlm_score
        feedback.append(f"VLM Reasoning: {parsed.get('reasoning', 'None')}")
    else:
        feedback.append("VLM verification failed to run")

    # Pass threshold
    # Needs at least 60 points and scene must be visible + interaction
    passed = (score >= 60) and (vlm_result.get("success", False)) and \
             parsed.get("scene_visible", False) and parsed.get("interaction_evident", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }