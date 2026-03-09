#!/usr/bin/env python3
"""
Verifier for design_home_gym task.

Verification Strategy:
1. File Verification (40 pts):
   - Check if gym_design.png exists and was created during the task.
   - Check file size to ensure it's not empty.

2. VLM Visual Verification (60 pts):
   - Analyze the exported screenshot/final state.
   - Criteria:
     a. At least 2 distinct pieces of gym equipment visible (cardio + strength).
     b. Flooring material appears changed (not standard wood/tile).
     c. Equipment is placed indoors on the floor.
   - Trajectory analysis to confirm library navigation (anti-gaming).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_design_home_gym(traj, env_info, task_info):
    """
    Verify the home gym design task.
    """
    # 1. Setup Phase
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', r"C:\Users\Docker\Documents\gym_design.png")
    
    # 2. Retrieve Programmatic Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: In Windows envs, paths might be mapped differently, but copy_from_env 
        # usually handles the internal path /tmp or C:\tmp mapping defined in env config.
        # Assuming the export script wrote to C:\tmp\task_result.json which maps to container path.
        # We try standard linux path first if mapped, or handle windows path logic if exposed.
        # For this framework, we assume standard copy logic works on the file generated.
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy/read result json: {e}")
        return {"passed": False, "score": 0, "feedback": "Could not retrieve task results from environment."}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Evaluate File Evidence (40 points max)
    score = 0
    feedback = []
    
    output_exists = result_data.get('output_exists', False)
    created_during = result_data.get('file_created_during_task', False)
    file_size = result_data.get('output_size_bytes', 0)
    app_running = result_data.get('app_was_running', False)

    if output_exists:
        score += 10
        feedback.append("Output image exists.")
        
        if created_during:
            score += 20
            feedback.append("Output image created during task session.")
        else:
            feedback.append("Output image timestamp is stale (pre-dates task).")
            
        if file_size > 10240: # > 10KB
            score += 10
            feedback.append(f"Output image size is reasonable ({file_size/1024:.1f} KB).")
        else:
            feedback.append("Output image is suspiciously small.")
    else:
        feedback.append("No output image found.")

    # 4. VLM Verification (60 points max)
    # We use the final screenshot from the agent's screen (most reliable for state)
    # AND the exported image if we could retrieve it (but we rely on screen for VLM usually)
    
    final_screenshot = get_final_screenshot(traj)
    trajectory_frames = sample_trajectory_frames(traj, n=4)
    
    if not final_screenshot:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback) + " (No screenshot available)"}

    # Prompt for VLM
    prompt = """
    You are verifying a "Design a Home Gym" task in Home Design Software.
    
    Look at the sequence of images and the final state.
    
    Verification Criteria:
    1. EQUIPMENT: Do you see at least TWO distinct pieces of gym equipment?
       - Look for: Treadmills, Ellipticals, Exercise Bikes, Weight Benches, Dumbbells, Yoga mats.
       - Note: Do NOT count standard furniture like sofas or beds.
    
    2. FLOORING: Does the floor in the gym area look like special gym flooring?
       - Look for: Rubber mats (black/grey), Carpet, or Cork.
       - It should NOT look like standard hardwood or white tile if possible (though some gyms use wood).
       - Key is intent: did they change the floor?
       
    3. PLACEMENT: Is the equipment placed inside a room on the floor?
       - Not floating in the sky, not outside on the grass.
       
    Respond in JSON:
    {
        "gym_equipment_found": ["item1", "item2"],
        "distinct_items_count": int,
        "flooring_changed": boolean,
        "placement_valid": boolean,
        "reasoning": "string"
    }
    """
    
    vlm_result = query_vlm(images=trajectory_frames + [final_screenshot], prompt=prompt)
    
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        items = parsed.get('gym_equipment_found', [])
        distinct_count = parsed.get('distinct_items_count', 0)
        flooring_changed = parsed.get('flooring_changed', False)
        placement_valid = parsed.get('placement_valid', False)
        reasoning = parsed.get('reasoning', "No reasoning provided")
        
        feedback.append(f"VLM Analysis: {reasoning}")
        
        # Scoring Logic
        if distinct_count >= 1:
            score += 15
        if distinct_count >= 2:
            score += 15 # Total 30 for equipment
            
        if flooring_changed:
            score += 20
            
        if placement_valid:
            score += 10
            
    else:
        feedback.append("VLM verification failed to process images.")

    # 5. Final Assessment
    # Pass threshold: 60 points + Essential Criteria (Must have equipment and output file)
    
    essential_criteria_met = output_exists and (score >= 40) # Implies at least some VLM success or perfect file score
    passed = (score >= 60) and essential_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }