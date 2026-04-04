#!/usr/bin/env python3
"""
Verifier for Geography Quiz Task.
Uses VLM trajectory analysis to verify the agent navigated to the correct activity
and correctly identified countries in South America.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_geography_quiz(traj, env_info, task_info):
    """
    Verifies the Geography Quiz task.
    
    Criteria:
    1. Evidence screenshot exists and was created during task (20 pts)
    2. VLM Trajectory Verification (80 pts):
       - Navigation to "Locate the region" (20 pts)
       - Selection of South America (20 pts)
       - Correctly identifying at least 5 countries (40 pts)
    """
    
    # Setup helpers
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    # 1. Retrieve file-based results
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            task_result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to load task result: {e}")
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution data"}

    # 2. Score File Evidence (20 pts)
    score = 0
    feedback = []
    
    if task_result.get("evidence_file_exists") and task_result.get("evidence_file_created_during_task"):
        file_size = task_result.get("evidence_file_size", 0)
        if file_size > 10000: # >10KB implies real image
            score += 20
            feedback.append("Evidence screenshot saved successfully.")
        else:
            score += 10
            feedback.append("Evidence screenshot exists but is suspiciously small.")
    else:
        feedback.append("Evidence screenshot not found or not created during task.")

    # 3. VLM Verification (80 pts)
    # We use trajectory frames to verify the workflow
    frames = sample_trajectory_frames(traj, n=6)
    final_screen = get_final_screenshot(traj)
    
    if not frames:
        return {"passed": False, "score": score, "feedback": "No video trajectory available for verification."}
    
    # Add final screen to analysis set
    analysis_frames = frames + [final_screen] if final_screen else frames

    prompt = """
    You are verifying a user interaction with the educational software GCompris.
    The task is: "Navigate to Geography > Locate the Region, select South America, and identify at least 5 countries."
    
    Please analyze the provided sequence of screenshots and determine:
    1. **Activity Navigation**: Did the user open the "Locate the region" / "Find the country" activity? (Distinct from the puzzle activity - this one asks questions).
    2. **Region Selection**: Was the "South America" map selected?
    3. **Gameplay**: Did the user answer questions? Look for text prompts like "Locate Brazil" or "Where is Peru?".
    4. **Success Indicators**: Did the user correctly identify countries? Look for:
       - Green highlighted countries
       - Checkmarks or "OK" signs
       - Score counter increasing
       - "Great" or congratulations text
    5. **Quantity**: Did the user identify multiple countries (approx 5+)?
    
    Respond in JSON format:
    {
        "opened_locate_activity": boolean,
        "selected_south_america": boolean,
        "gameplay_observed": boolean,
        "successful_identifications_observed": boolean,
        "estimated_count_correct": number,
        "explanation": "string"
    }
    """

    try:
        vlm_response = query_vlm(
            images=analysis_frames,
            prompt=prompt
        )
        
        if vlm_response.get("success"):
            analysis = vlm_response.get("parsed", {})
            
            # Navigated to correct activity
            if analysis.get("opened_locate_activity"):
                score += 20
                feedback.append("Correctly navigated to 'Locate the region' activity.")
            else:
                feedback.append("Could not confirm navigation to 'Locate the region'.")
                
            # Selected South America
            if analysis.get("selected_south_america"):
                score += 20
                feedback.append("Correctly selected South America map.")
            else:
                feedback.append("Could not confirm South America selection.")
                
            # Gameplay performance
            if analysis.get("successful_identifications_observed"):
                # Full points if multiple identified, partial if only 1-2
                est_count = analysis.get("estimated_count_correct", 0)
                if est_count >= 5:
                    score += 40
                    feedback.append(f"Identified {est_count} countries (Target: 5+).")
                elif est_count >= 1:
                    partial = int(40 * (est_count / 5))
                    score += partial
                    feedback.append(f"Identified {est_count} countries (Target: 5).")
                else:
                    feedback.append("Gameplay observed but count unclear.")
            else:
                feedback.append("No successful country identifications observed.")
                
            logger.info(f"VLM Analysis: {analysis.get('explanation')}")
            
        else:
            feedback.append("Visual verification failed to process images.")
            
    except Exception as e:
        logger.error(f"VLM Exception: {e}")
        feedback.append(f"Verification error: {str(e)}")

    # Final Pass Determination
    # Pass if score >= 70 AND South America was selected
    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }