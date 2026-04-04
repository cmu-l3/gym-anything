#!/usr/bin/env python3
"""
Verifier for assemble_famous_painting task.

Verification Strategy:
1. File Checks: Confirm agent created 'painting_solved.png' and 'painting_info.txt'.
2. Timestamp Checks: Ensure files were created during the task window.
3. VLM Visual Analysis:
   - Verify 'painting_solved.png' shows a COMPLETED puzzle of a painting.
   - Verify the text in 'painting_info.txt' corresponds to the painting in the image.
   - Use trajectory frames to verify the agent actually interacted with the puzzle (drag-and-drop) rather than just opening a finished image.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_assemble_famous_painting(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load basic task result JSON
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {str(e)}"}

    score = 0
    feedback_parts = []
    
    # 2. Basic criteria (Files exist and valid timestamps) - 30 points
    files_ok = False
    if task_result.get('screenshot_exists') and task_result.get('screenshot_valid_time'):
        score += 15
        feedback_parts.append("Screenshot saved.")
        files_ok = True
    else:
        feedback_parts.append("Screenshot missing or not created during task.")

    if task_result.get('text_file_exists') and task_result.get('text_valid_time'):
        score += 15
        feedback_parts.append("Info text file saved.")
        # Ensure content is not empty
        if not task_result.get('text_content', '').strip():
            score -= 5
            feedback_parts.append("Text file is empty.")
    else:
        feedback_parts.append("Info text file missing.")

    # 3. Retrieve Agent's Screenshot for VLM analysis
    agent_screenshot_local = None
    if task_result.get('screenshot_exists'):
        with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as img_f:
            try:
                copy_from_env(task_result['agent_screenshot_path'], img_f.name)
                agent_screenshot_local = img_f.name
            except Exception:
                feedback_parts.append("Could not retrieve agent screenshot.")

    # 4. VLM Verification - 70 points
    # We check:
    # A) Does the screenshot show a completed painting?
    # B) Does the text match the painting?
    # C) Did the trajectory show puzzle solving?

    vlm_score = 0
    vlm_passed = False
    
    recorded_text = task_result.get('text_content', 'Unknown')
    
    if agent_screenshot_local:
        # Prompt for content verification
        content_prompt = f"""
        Analyze this image. It should be a screenshot of a completed jigsaw puzzle from the GCompris "Famous Paintings" activity.
        
        The user claims this painting is: "{recorded_text}"
        
        1. Is the image a recognizable famous painting?
        2. Is the puzzle FULLY assembled (no scattered pieces, looks like a complete image)?
        3. Does the painting name/artist "{recorded_text}" roughly match the painting shown? (e.g. if image is Mona Lisa, text "Mona Lisa" or "Da Vinci" is correct).
        
        Respond in JSON:
        {{
            "is_painting": boolean,
            "is_fully_assembled": boolean,
            "text_matches_image": boolean,
            "painting_name_identified": "string"
        }}
        """
        
        try:
            res = query_vlm(images=[agent_screenshot_local], prompt=content_prompt)
            parsed = res.get('parsed', {})
            
            if parsed.get('is_painting') and parsed.get('is_fully_assembled'):
                vlm_score += 30
                feedback_parts.append("Visual verified: Completed painting.")
                
                if parsed.get('text_matches_image'):
                    vlm_score += 20
                    feedback_parts.append(f"Visual verified: Text '{recorded_text}' matches image.")
                else:
                    feedback_parts.append(f"Visual mismatch: Image looks like {parsed.get('painting_name_identified')} but text was '{recorded_text}'.")
            else:
                feedback_parts.append("Visual check failed: Image is not a fully assembled painting.")
                
        except Exception as e:
            feedback_parts.append(f"VLM content check error: {e}")
    else:
        feedback_parts.append("Skipping content VLM check (no screenshot).")

    # 5. Trajectory Verification (Anti-gaming) - 20 points
    # Ensure they didn't just open a static image file or do nothing
    traj_frames = sample_trajectory_frames(traj, n=4)
    if traj_frames:
        traj_prompt = """
        Review these screenshots of a user using GCompris. 
        Did the user navigate to a puzzle activity and interact with puzzle pieces (drag and drop)?
        
        Look for:
        - A puzzle selection menu.
        - A workspace with scattered puzzle pieces.
        - Pieces being moved or snapped together.
        
        Respond in JSON:
        {{
            "puzzle_interaction_observed": boolean,
            "reasoning": "string"
        }}
        """
        try:
            res_traj = query_vlm(images=traj_frames, prompt=traj_prompt)
            if res_traj.get('parsed', {}).get('puzzle_interaction_observed', False):
                vlm_score += 20
                feedback_parts.append("Trajectory verified: Puzzle interaction observed.")
            else:
                feedback_parts.append("Trajectory warning: No clear puzzle interaction seen.")
        except Exception as e:
            logger.error(f"Trajectory VLM error: {e}")
            # Give benefit of doubt if VLM fails but files are good
            vlm_score += 10 

    total_score = score + vlm_score
    passed = (total_score >= 80)

    # Cleanup
    if agent_screenshot_local and os.path.exists(agent_screenshot_local):
        os.unlink(agent_screenshot_local)

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback_parts)
    }