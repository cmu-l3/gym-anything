#!/usr/bin/env python3
"""
Verifier for design_guest_bathroom task.
Checks if the bathroom design was exported and contains required fixtures using VLM.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_design_guest_bathroom(traj, env_info, task_info):
    """
    Verify the bathroom design task.
    
    Criteria:
    1. Output image file exists and is valid (File-based)
    2. Output image was created during the task (Anti-gaming)
    3. VLM: Exported image (or final screen) shows a Bathtub
    4. VLM: Exported image (or final screen) shows a Toilet
    5. VLM: Exported image (or final screen) shows a Sink/Vanity
    """
    
    # 1. Setup and retrieve result JSON from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    score_weights = metadata.get('score_weights', {
        "file_exists": 10,
        "file_valid": 10,
        "vlm_content": 60,
        "vlm_workflow": 20
    })

    # Read result.json
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Container path is Windows style, but copy_from_env handles the mapping
        copy_from_env("C:\\Windows\\Temp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution results"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. File-based Verification
    score = 0
    feedback_parts = []
    
    output_exists = result_data.get('output_exists', False)
    file_created = result_data.get('file_created_during_task', False)
    file_size = result_data.get('output_size_bytes', 0)
    
    if output_exists:
        score += score_weights['file_exists']
        feedback_parts.append("Output file found")
        
        if file_created:
            score += score_weights['file_valid'] / 2
            feedback_parts.append("File created during task")
        else:
            feedback_parts.append("File timestamp invalid (pre-dated)")
            
        if file_size > 5000: # Arbitrary threshold for non-empty image
            score += score_weights['file_valid'] / 2
        else:
            feedback_parts.append("File size too small")
    else:
        feedback_parts.append("Output file NOT found")

    # 3. VLM Verification (Content)
    # Ideally, we check the exported file itself. If not easy to render in VLM pipeline, 
    # we fallback to final screenshot from the agent's view.
    # We'll use the final screenshot provided by the framework/trajectory for simplicity and reliability.
    
    final_screenshot = get_final_screenshot(traj)
    
    # Prompt for content verification
    content_prompt = """
    Analyze this image of a home design software interface or exported design.
    Look for a Bathroom layout.
    
    Identify if the following items are visible in the 3D scene/design:
    1. A Bathtub (any shape/style)
    2. A Toilet
    3. A Bathroom Sink or Vanity
    
    Respond in JSON:
    {
        "bathtub_visible": true/false,
        "toilet_visible": true/false,
        "sink_visible": true/false,
        "items_overlapping": true/false,
        "room_looks_like_bathroom": true/false
    }
    """
    
    vlm_content_result = query_vlm(image=final_screenshot, prompt=content_prompt)
    
    content_score = 0
    if vlm_content_result and vlm_content_result.get('success'):
        parsed = vlm_content_result.get('parsed', {})
        items_found = 0
        if parsed.get('bathtub_visible'): items_found += 1
        if parsed.get('toilet_visible'): items_found += 1
        if parsed.get('sink_visible'): items_found += 1
        
        # Calculate content score (proportional)
        if items_found > 0:
            content_score = (items_found / 3) * score_weights['vlm_content']
            feedback_parts.append(f"VLM identified {items_found}/3 required bathroom items")
        else:
            feedback_parts.append("VLM could not identify bathroom fixtures in the final view")
            
        if parsed.get('room_looks_like_bathroom'):
            feedback_parts.append("Scene resembles a bathroom")
        
        # Penalize overlapping if detected? (Optional)
    else:
        feedback_parts.append("VLM analysis failed")

    score += content_score

    # 4. VLM Verification (Workflow/Trajectory)
    # Check if they actually went to the library
    trajectory_frames = sample_trajectory_frames(traj, n=4)
    workflow_prompt = """
    Analyze these screenshots of a user using DreamPlan Home Design software.
    Did the user:
    1. Open a furniture/object library?
    2. Navigate to 'Bathroom', 'Plumbing', or 'Interior' categories?
    3. Place multiple objects into the scene?
    
    Respond in JSON:
    {
        "library_opened": true/false,
        "bathroom_category_seen": true/false,
        "placement_actions_observed": true/false
    }
    """
    
    vlm_workflow_result = query_vlm(images=trajectory_frames, prompt=workflow_prompt)
    
    workflow_score = 0
    if vlm_workflow_result and vlm_workflow_result.get('success'):
        parsed = vlm_workflow_result.get('parsed', {})
        if parsed.get('library_opened') or parsed.get('bathroom_category_seen'):
            workflow_score += score_weights['vlm_workflow']
            feedback_parts.append("Workflow verification passed (Library/Category accessed)")
    
    score += workflow_score
    
    # Final Decision
    passed = score >= 60 and output_exists and file_created
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": "; ".join(feedback_parts)
    }