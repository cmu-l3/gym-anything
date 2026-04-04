#!/usr/bin/env python3
"""
Verifier for stage_kitchen_counters task in DreamPlan Home Design.

Verification Strategy:
1. File Check: Confirm 'KitchenStaging.dpp' was saved and modified during the task.
2. VLM Trajectory Check: Verify the agent navigated to the kitchen and selected appliances.
3. VLM Final State Check: Verify appliances are visible on the counters.

The task is visual, so VLM is the primary verification method for the "Staging" aspect.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM PROMPTS
PROCESS_PROMPT = """You are evaluating an agent using home design software.
Look at this sequence of screenshots.
Did the agent:
1. Navigate to a kitchen area (cabinets, sink visible)?
2. Open a furniture/object library?
3. Select small appliances (toaster, coffee maker, microwave, blender, etc.)?
4. Attempt to place them on the countertops?

Respond in JSON:
{
    "kitchen_visited": true/false,
    "library_opened": true/false,
    "appliances_selected": true/false,
    "placement_attempted": true/false
}
"""

FINAL_STATE_PROMPT = """Look at this final design of a kitchen.
The goal was to stage the countertops with small appliances.

Check for:
1. Are there at least two DIFFERENT small appliances visible (e.g. Toaster AND Coffee Maker)?
2. Are they resting ON the countertop surface (not floating in air, not on the floor)?
3. Does the scene look like a kitchen?

Respond in JSON:
{
    "appliance_count": <number>,
    "appliances_detected": ["list", "of", "items"],
    "on_countertop": true/false,
    "different_types": true/false,
    "is_kitchen": true/false
}
"""

def verify_stage_kitchen_counters(traj, env_info, task_info):
    # 1. Setup and imports
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm', None) # Assuming this is available in the verifier context
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # 2. Retrieve JSON result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 3. Helper to get VLM results
    # (In a real implementation, we would import standard VLM utils from the framework)
    # Here we mock the call structure based on instructions
    def run_vlm(prompt, images):
        if not query_vlm:
            logger.warning("VLM function not available")
            return None
        try:
            return query_vlm(prompt=prompt, images=images)
        except Exception as e:
            logger.error(f"VLM error: {e}")
            return None

    # 4. Scoring Logic
    score = 0
    feedback = []
    
    # Criterion 1: File Existence & Anti-Gaming (20 pts)
    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    
    if output_exists and file_created:
        score += 20
        feedback.append("Project saved successfully.")
    elif output_exists:
        score += 10
        feedback.append("Project file exists but timestamp check failed (check system clocks).")
    else:
        feedback.append("Project file not saved.")

    # Criterion 2: VLM Process Verification (Trajectory) (30 pts)
    # We need to sample frames from traj
    # Assuming traj is a list of steps with 'screenshot' path or data
    # This part depends on framework implementation of 'traj'
    # We will assume we can pass the object to the VLM helper provided by the system
    
    # Placeholder for framework-specific image extraction
    # images = [step['screenshot'] for step in traj[::max(1, len(traj)//5)]] 
    
    vlm_process = run_vlm(PROCESS_PROMPT, traj) # Pass full traj, let wrapper handle sampling
    
    process_score = 0
    if vlm_process and vlm_process.get('success'):
        parsed = vlm_process.get('parsed', {})
        if parsed.get('kitchen_visited'): process_score += 5
        if parsed.get('library_opened'): process_score += 10
        if parsed.get('appliances_selected'): process_score += 10
        if parsed.get('placement_attempted'): process_score += 5
        feedback.append(f"Process check: {process_score}/30 points.")
    else:
        feedback.append("Could not verify workflow process (VLM unavailable or failed).")
    
    score += process_score

    # Criterion 3: VLM Final State Verification (50 pts)
    # We need the final screenshot. 
    # result['screenshot_path'] is the path inside container.
    # We need to copy it out to analyze, OR pass the trajectory's last frame.
    # Usually traj[-1] contains the final state.
    
    vlm_final = run_vlm(FINAL_STATE_PROMPT, [traj[-1]] if traj else [])
    
    final_score = 0
    passed_final = False
    
    if vlm_final and vlm_final.get('success'):
        parsed = vlm_final.get('parsed', {})
        
        # Is it a kitchen?
        if parsed.get('is_kitchen'): 
            final_score += 10
        
        # Appliances count
        count = parsed.get('appliance_count', 0)
        detected = parsed.get('appliances_detected', [])
        
        if count >= 2:
            final_score += 20
        elif count == 1:
            final_score += 10
            
        # Placement
        if parsed.get('on_countertop'):
            final_score += 10
            
        # Diversity
        if parsed.get('different_types'):
            final_score += 10
            
        feedback.append(f"Final design check: {final_score}/50 points. Detected: {', '.join(detected)}")
        
        if count >= 1 and parsed.get('on_countertop'):
            passed_final = True
            
    else:
        feedback.append("Could not verify final design (VLM unavailable or failed).")

    score += final_score

    # Final Pass Determination
    # Must save file AND have visible appliances on counter
    passed = (output_exists and passed_final and score >= 60)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }