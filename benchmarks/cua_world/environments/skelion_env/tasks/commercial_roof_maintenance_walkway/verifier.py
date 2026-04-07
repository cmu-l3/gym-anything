#!/usr/bin/env python3
"""
Verifier for commercial_roof_maintenance_walkway task.

ROBUST MULTI-SIGNAL VERIFICATION:
1. File exists and was created during the task timeframe (Anti-gaming) (15 points)
2. File size reflects actual modeling work (15 points)
3. VLM: 3D Building is present in the trajectory (10 points)
4. VLM: Solar Panels are present on the roof (20 points)
5. VLM: Central walkway gap explicitly separating arrays (CRITICAL) (30 points)
6. VLM: Tilted panel orientation visible (10 points)

Pass threshold: 75% AND Walkway visible AND File created
"""

import os
import json
import tempfile
import logging
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are verifying if a computer agent successfully completed a commercial solar panel layout task in SketchUp.

TASK: Model a flat-roofed commercial building, define a 2-meter walkway down the center, and insert tilted solar panels on the remaining roof areas using the Skelion plugin.

Look at these screenshots from the agent's trajectory and the final state. Determine:
1. Is there a 3D building modeled with a flat roof?
2. Are there solar panels placed on the roof? (Usually appear as blue/dark grids or rectangular components)
3. Is there a clear, distinct walkway (empty gap) running through the middle of the roof, splitting the panels into two distinct groups/arrays? (This is CRITICAL: panels should not cover the entire roof continuously)
4. Are the panels tilted? (Not perfectly flat against the roof, but showing some angle/shadows)

Respond ONLY in valid JSON format:
{
    "building_present": true/false,
    "panels_present": true/false,
    "walkway_gap_visible": true/false,
    "panels_tilted": true/false,
    "confidence": "low" | "medium" | "high",
    "reasoning": "Brief explanation of what you see"
}
"""

def verify_walkway_task(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_file_size_kb = metadata.get('min_file_size_kb', 80)
    
    score = 0
    feedback_parts = []
    
    # ================================================================
    # 1. FILE & METADATA VERIFICATION
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Retrieve the result exported from the Windows container
        copy_from_env("C:\\Temp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to read result JSON: {e}")
        result = {}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    file_size_bytes = result.get('output_size_bytes', 0)
    file_size_kb = file_size_bytes / 1024.0
    
    file_criteria_met = False
    
    if output_exists and file_created:
        score += 15
        feedback_parts.append("File newly created successfully")
        if file_size_kb >= min_file_size_kb:
            score += 15
            feedback_parts.append(f"Acceptable file size ({file_size_kb:.1f}KB)")
            file_criteria_met = True
        else:
            score += 5
            feedback_parts.append(f"Warning: File size small ({file_size_kb:.1f}KB)")
    elif output_exists:
        feedback_parts.append("File exists but was NOT created during this task session")
    else:
        feedback_parts.append("Expected SketchUp .skp output file not found")
        
    # ================================================================
    # 2. VLM VISUAL VERIFICATION
    # ================================================================
    if not query_vlm:
        feedback_parts.append("VLM query function not available")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    # Sample multiple frames to capture the modeling process & final layout
    frames = sample_trajectory_frames(traj, n=3)
    final = get_final_screenshot(traj)
    images = frames + [final] if final else frames
    
    if not images:
        feedback_parts.append("No screenshots available for VLM")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    vlm_result = query_vlm(
        prompt=VERIFICATION_PROMPT,
        images=images
    )
    
    walkway_visible = False
    
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("building_present"):
            score += 10
            feedback_parts.append("VLM: Building confirmed")
            
        if parsed.get("panels_present"):
            score += 20
            feedback_parts.append("VLM: Solar panels confirmed")
            
        if parsed.get("walkway_gap_visible"):
            score += 30
            walkway_visible = True
            feedback_parts.append("VLM: Walkway gap correctly implemented")
        else:
            feedback_parts.append("VLM: Walkway gap missing/failed (CRITICAL)")
            
        if parsed.get("panels_tilted"):
            score += 10
            feedback_parts.append("VLM: Tilted orientation confirmed")
    else:
        feedback_parts.append(f"VLM verification failed: {vlm_result.get('error', 'Unknown')}")
        
    # ================================================================
    # FINAL SCORING
    # ================================================================
    
    # Must explicitly have the walkway modeled and successfully output the file
    key_criteria_met = walkway_visible and file_criteria_met
    passed = score >= 75 and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "file_exists": output_exists,
            "file_size_kb": file_size_kb,
            "walkway_visible": walkway_visible,
            "vlm_reasoning": parsed.get("reasoning", "") if vlm_result.get("success") else ""
        }
    }