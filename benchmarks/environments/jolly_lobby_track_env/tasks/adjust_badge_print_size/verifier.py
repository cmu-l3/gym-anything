#!/usr/bin/env python3
"""
Verifier for adjust_badge_print_size task.

Verifies that the agent configured visitor badge dimensions to:
- Width: 3.5"
- Height: 2.25"
- Margins: 0.1"

Strategy:
1. Programmatic: Check if config files were modified and contain target strings.
2. VLM: Analyze trajectory to confirm agent entered the correct settings in the UI.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt to verify the UI interaction
VLM_PROMPT = """
You are verifying if a user correctly adjusted badge print settings in a software application.

The required settings are:
- Badge Width: 3.5 inches
- Badge Height: 2.25 inches
- Margins (Top/Bottom/Left/Right): 0.1 inches

Look at the provided screenshots of the user's workflow. 
1. Did the user open a "Page Setup", "Badge Settings", "Printer Settings", or "Template Designer" dialog?
2. Can you see fields for Width/Height or Page Size?
3. Did the user enter "3.5" for width and "2.25" for height?
4. Did the user set margins to "0.1"?
5. Did the user click OK, Save, or Apply?

Return a JSON object with:
{
  "settings_dialog_opened": boolean,
  "width_correct": boolean,
  "height_correct": boolean,
  "margins_correct": boolean,
  "save_action_observed": boolean,
  "confidence": "high" | "medium" | "low"
}
"""

def verify_adjust_badge_print_size(traj, env_info, task_info):
    """
    Verify badge dimension adjustment using VLM and file system evidence.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    # 1. Load Programmatic Evidence (File modifications)
    task_result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. VLM Verification
    frames = sample_trajectory_frames(traj, n=6)
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        frames.append(final_screenshot)

    vlm_score_data = {"score": 0, "feedback": []}
    
    if frames:
        try:
            vlm_response = query_vlm(
                images=frames,
                prompt=VLM_PROMPT
            )
            parsed = vlm_response.get("parsed", {})
            logger.info(f"VLM Analysis: {parsed}")
            
            if parsed.get("settings_dialog_opened"):
                vlm_score_data["score"] += 20
                vlm_score_data["feedback"].append("Opened settings dialog.")
            
            if parsed.get("width_correct"):
                vlm_score_data["score"] += 20
                vlm_score_data["feedback"].append("Set width to 3.5\".")
            
            if parsed.get("height_correct"):
                vlm_score_data["score"] += 20
                vlm_score_data["feedback"].append("Set height to 2.25\".")
                
            if parsed.get("margins_correct"):
                vlm_score_data["score"] += 20
                vlm_score_data["feedback"].append("Set margins to 0.1\".")
                
            if parsed.get("save_action_observed"):
                vlm_score_data["score"] += 10
                vlm_score_data["feedback"].append("Saved settings.")
                
        except Exception as e:
            logger.error(f"VLM query failed: {e}")
            vlm_score_data["feedback"].append("VLM verification failed.")
    
    # 3. Combine Scores
    score = vlm_score_data["score"]
    feedback = list(vlm_score_data["feedback"])
    
    # Bonus/Corroboration from file system (Anti-gaming)
    # If the app saved config files containing our numbers, that's strong evidence
    file_evidence_score = 0
    if task_result.get("modified_files_detected"):
        file_evidence_score += 5
        # If we see the specific numbers written to disk, we trust the agent more
        if task_result.get("found_width") and task_result.get("found_height"):
            file_evidence_score += 10
            feedback.append("Configuration files updated with correct dimensions.")
    
    # If VLM missed something but files prove it, bump the score
    # (e.g., VLM didn't see the exact moment of typing, but file has '3.5')
    if score < 90 and task_result.get("found_width") and task_result.get("found_height"):
        score = max(score, 80) # Grant pass if file evidence is strong
    
    # Add small bonus for file evidence if not already maxed
    score = min(100, score + file_evidence_score)

    # Penalize if no files modified (suggests "Cancel" or no Save)
    if not task_result.get("modified_files_detected") and score > 50:
        feedback.append("Warning: No configuration file changes detected (did you save?).")
        # We don't fail purely on this because Wine file I/O can be weird or buffered,
        # but we deduct a little if we were unsure.
        if score == 100: 
            score = 95

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }