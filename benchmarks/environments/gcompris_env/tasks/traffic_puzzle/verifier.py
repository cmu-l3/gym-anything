#!/usr/bin/env python3
"""
Verifier for the GCompris Traffic Puzzle task.

Scoring Breakdown (Total 100):
1. Programmatic Checks (20 pts):
   - Agent saved a screenshot file: 10 pts
   - GCompris is running at the end: 10 pts
2. VLM Trajectory Verification (80 pts):
   - Traffic activity was opened (grid visible): 25 pts
   - Vehicles were moved (state change): 25 pts
   - Level solved (success state visible): 30 pts

Input:
- task_result.json (from export_result.sh)
- Trajectory screenshots (handled by VLM helper)
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any, List

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# VLM Prompt Templates
TRAJECTORY_ANALYSIS_PROMPT = """You are analyzing a sequence of screenshots from an agent using GCompris educational software. 
The agent's goal is to play the 'Traffic' activity (a Rush Hour-style sliding block puzzle).

Review the screenshots and answer the following questions:

1. ACTIVITY_OPENED: Do you see the Traffic puzzle interface? It consists of a square grid containing colored rectangular blocks (cars/trucks) and an exit hole on one side.
2. INTERACTION: Do the vehicle blocks move between frames? (e.g., a car is in one position in frame A and a different position in frame B).
3. SUCCESS: Is the puzzle solved? Look for:
   - The target car (usually red/special color) reaching the exit edge.
   - A 'Congratulations' or 'Great' animation.
   - The game transitioning to a new, harder level (Level 2).

Format your response as JSON:
{
  "activity_opened": true/false,
  "interaction_observed": true/false,
  "level_solved": true/false,
  "confidence": "low|medium|high",
  "reasoning": "Description of what you see..."
}
"""

def verify_traffic_puzzle(traj, env_info, task_info):
    """
    Verifies the Traffic Puzzle task using VLM for visual logic and file checks for basic compliance.
    """
    # 1. Setup and imports
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm') # Hypothetical VLM hook provided by framework
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 2. Retrieve Programmatic Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Calculate Programmatic Score (Max 20)
    score = 0
    feedback_lines = []

    # Check 1: App Running (10 pts)
    if result_data.get("app_running", False):
        score += 10
        feedback_lines.append("✓ GCompris was running at the end.")
    else:
        feedback_lines.append("✗ GCompris was NOT running.")

    # Check 2: Screenshot Saved (10 pts)
    # We check if it exists AND was created during the task window
    if result_data.get("screenshot_exists", False) and result_data.get("screenshot_valid_time", False):
        size_kb = result_data.get("screenshot_size_bytes", 0) / 1024
        if size_kb > 5: # Minimal size check for non-empty image
            score += 10
            feedback_lines.append(f"✓ Screenshot saved correctly ({int(size_kb)}KB).")
        else:
            feedback_lines.append(f"✗ Screenshot saved but too small ({int(size_kb)}KB).")
    else:
        feedback_lines.append("✗ Screenshot not found or created before task started.")

    # 4. VLM Verification (Max 80)
    # If we don't have VLM capability, we return the programmatic score (for testing/fallback)
    if not query_vlm:
        feedback_lines.append("! VLM verification unavailable. Returning partial score.")
        return {"passed": False, "score": score, "feedback": "\n".join(feedback_lines)}

    # Sample trajectory frames
    # We assume 'traj' contains a list of frame objects or paths. 
    # Framework specific: accessing images from traj object.
    # Assuming gym_anything style: traj.frames or similar.
    # We will pass the FINAL screenshot from the export script as well if available.
    
    # NOTE: In a real implementation, we would extract frames from 'traj'. 
    # For this script, we'll assume query_vlm handles 'images=traj' or we extract them.
    # Here we simulate the call structure:
    
    try:
        # Use helper from framework (hypothetical) or assume traj is iterable of images
        # images_to_analyze = sample_trajectory(traj, 5) 
        # For this template, we simply pass the whole traj object to the framework's VLM wrapper 
        # if it supports it, or we rely on the framework injecting the images.
        
        vlm_response = query_vlm(
            prompt=TRAJECTORY_ANALYSIS_PROMPT,
            images=traj, # Pass full trajectory for analysis
            json_response=True
        )
        
        if vlm_response and isinstance(vlm_response, dict):
            # Parse VLM output
            vlm_data = vlm_response.get("parsed", {})
            if not vlm_data:
                # Fallback if parsed key isn't present but response is the dict
                vlm_data = vlm_response
            
            # Score VLM criteria
            
            # Criterion 3: Activity Opened (25 pts)
            if vlm_data.get("activity_opened", False):
                score += 25
                feedback_lines.append("✓ VLM confirmed Traffic activity was opened.")
            else:
                feedback_lines.append("✗ VLM did not see the Traffic activity.")

            # Criterion 4: Interaction (25 pts)
            if vlm_data.get("interaction_observed", False):
                score += 25
                feedback_lines.append("✓ VLM confirmed vehicles were moved.")
            else:
                feedback_lines.append("✗ VLM did not observe puzzle interaction.")

            # Criterion 5: Solved (30 pts)
            if vlm_data.get("level_solved", False):
                score += 30
                feedback_lines.append("✓ VLM confirmed Level 1 was solved.")
            else:
                feedback_lines.append("✗ VLM did not see completion state.")
                
            feedback_lines.append(f"VLM Reasoning: {vlm_data.get('reasoning', 'No reasoning provided')}")

        else:
            feedback_lines.append("! VLM Analysis failed or returned invalid format.")

    except Exception as e:
        feedback_lines.append(f"! Error during VLM analysis: {str(e)}")

    # 5. Final Decision
    # Pass threshold: 60 points.
    # This requires at least opening the activity + moving cars + programmatic checks,
    # OR solving it + programmatic checks.
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines)
    }