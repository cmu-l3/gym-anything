#!/usr/bin/env python3
"""
Verifier for the warehouse_skylight_grid_solar task.

Verification Strategy:
1. File Metadata: Ensures the SKP file was saved to the correct path, 
   has substantial size indicating actual geometry, and was created *during* the task.
2. VLM Trajectory Assessment: Reviews frames across the agent's workflow to confirm:
   - Building geometry creation.
   - Skylight array logic.
   - Solar panel instantiation.
   - Spatial avoidance constraint (panels don't cover skylights).
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_warehouse_skylight_grid_solar(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_size_bytes = metadata.get('min_size_bytes', 80000)

    # 1. Retrieve the file metadata results via container copy
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\Documents\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    file_size = result.get('output_size_bytes', 0)
    
    score = 0
    feedback = []
    
    # Metadata Scoring
    if output_exists:
        score += 10
        feedback.append("File saved successfully.")
        if file_created:
            score += 10
            feedback.append("File created during task.")
        else:
            feedback.append("Warning: File modified timestamp is prior to task start.")
    else:
        feedback.append("File was NOT saved to the expected path.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}
        
    if file_size > min_size_bytes:
        score += 10
        feedback.append(f"File size OK ({file_size/1024:.1f} KB).")
    else:
        feedback.append(f"File size unusually small ({file_size/1024:.1f} KB). May lack required geometry.")

    # 2. VLM Verification Pipeline
    if not query_vlm:
        feedback.append("VLM query function not available for visual verification.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}
        
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    
    # We sample the trajectory so we can see the progression of building > cutting > paneling
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    images = frames + [final] if final else frames
    
    if not images:
        feedback.append("No screenshots available for VLM verification.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}
        
    vlm_prompt = """You are verifying a 3D modeling and solar design task in SketchUp.
The objective was to:
1. Create a rectangular warehouse.
2. Add a 2x3 grid of skylights (6 total) on the flat roof.
3. Insert an array of tilted solar panels using a plugin.
4. CRITICAL: The solar panels must AVOID covering the skylights. The skylights should clearly break up the solar array.

Review these trajectory frames and determine if the objectives were met. 
Return ONLY a valid JSON object:
{
    "has_building": true/false,
    "has_skylights": true/false,
    "has_solar_panels": true/false,
    "panels_avoid_skylights": true/false,
    "reasoning": "Brief explanation of what is visible in the frames."
}"""

    vlm_res = query_vlm(images=images, prompt=vlm_prompt)
    
    if not vlm_res.get("success"):
        feedback.append("VLM verification failed to process.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}
        
    parsed = vlm_res.get("parsed", {})
    
    # Robust parsing in case the VLM wrapped it in markdown codeblocks
    if not isinstance(parsed, dict):
        try:
            import re
            match = re.search(r'\{.*\}', str(parsed), re.DOTALL)
            if match:
                parsed = json.loads(match.group(0))
            else:
                parsed = json.loads(str(parsed))
        except Exception:
            parsed = {}
            
    vlm_building = parsed.get("has_building", False)
    vlm_skylights = parsed.get("has_skylights", False)
    vlm_panels = parsed.get("has_solar_panels", False)
    vlm_avoid = parsed.get("panels_avoid_skylights", False)
    
    if vlm_building:
        score += 10
        feedback.append("Building detected.")
    if vlm_skylights:
        score += 20
        feedback.append("Skylight grid detected.")
    if vlm_panels:
        score += 20
        feedback.append("Solar panels present.")
    if vlm_avoid:
        score += 20
        feedback.append("Panels successfully avoided skylights.")
    else:
        feedback.append("Panels failed to avoid skylights (or verification inconclusive).")

    # Final Pass Logic: must achieve at least an 80 and crucially have avoided obstructions
    is_passed = (score >= 80) and output_exists and vlm_panels and vlm_avoid
    
    return {
        "passed": is_passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }