#!/usr/bin/env python3
"""
Verifier for facade_solar_panels task.

VERIFICATION STRATEGY:
1. File-based programmatic check: 
   - Ensure the .skp file is created at the exact required path.
   - Verify file size indicates a non-empty model (>100KB, ideal >200KB).
   - Check anti-gaming timestamp (modified after task started).
2. Trajectory VLM check:
   - Uses sequence frames to ensure building was modeled.
   - Confirms Skelion was interacted with.
   - Verifies solar panels are explicitly on a VERTICAL wall (façade), not a roof.
   - Checks for grid arrangement of panels.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are verifying if a computer agent successfully completed a SketchUp solar design task using the Skelion plugin.
The task was to design a vertical façade-mounted solar panel array on a south-facing wall of a rectangular commercial building.

Analyze the provided sequence of screenshots from the task trajectory (which includes the final state) and determine the following:

1. building_created: Is there a 3D rectangular box/building visible in the SketchUp viewport?
2. skelion_used: Is the Skelion plugin dialog, toolbar, or settings panel ever opened or interacted with?
3. panels_on_vertical_wall: In the later/final frames, are there solar panel components visibly arranged on a vertical wall face of the building (not flat on the roof, not on the ground)?
4. grid_arrangement: Are the panels on the wall arranged in a grid pattern with multiple rows and columns?
5. location_set: Is there any evidence that the location was set to Denver, Colorado (e.g., Geo-location dialog visible in any frame)?

Respond strictly in JSON format with boolean values for each criteria:
{
    "building_created": true/false,
    "skelion_used": true/false,
    "panels_on_vertical_wall": true/false,
    "grid_arrangement": true/false,
    "location_set": true/false,
    "reasoning": "brief explanation of your visual findings"
}
"""

def verify_facade_solar_panels(traj, env_info, task_info):
    """Verify the agent successfully created a building and mounted solar panels on the façade."""
    
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100
    
    # 1. Evaluate programmatic state (from export_result.ps1)
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    output_exists = result.get('output_exists', False)
    file_size = result.get('output_size_bytes', 0)
    file_mtime = result.get('file_mtime', 0)
    task_start = result.get('task_start', 0)
    
    # Anti-gaming: File must exist and be modified after start
    if output_exists:
        if file_mtime >= task_start:
            score += 10
            feedback_parts.append("✅ File created/modified during task (+10)")
            
            # File size checks (empty template is ~50KB)
            if file_size >= 200000:
                score += 10
                feedback_parts.append(f"✅ File size robust ({file_size/1024:.1f}KB) (+10)")
            elif file_size >= 100000:
                score += 5
                feedback_parts.append(f"⚠️ File size minimal ({file_size/1024:.1f}KB) (+5)")
            else:
                feedback_parts.append(f"❌ File size too small ({file_size/1024:.1f}KB) - likely empty")
        else:
            feedback_parts.append("❌ File timestamp predates task start (Pre-existing file)")
    else:
        feedback_parts.append("❌ Required .skp model file not found at expected path")

    # 2. Evaluate visual trajectory via VLM
    vlm_metrics = {
        "building_created": False,
        "skelion_used": False,
        "panels_on_vertical_wall": False,
        "grid_arrangement": False,
        "location_set": False
    }
    
    if not query_vlm:
        feedback_parts.append("❌ VLM query function not available for trajectory verification")
    else:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Sample frames from trajectory plus the final screenshot
        frames = sample_trajectory_frames(traj, n=5)
        final_frame = get_final_screenshot(traj)
        images = frames + [final_frame] if final_frame else frames
        
        if not images:
            feedback_parts.append("❌ No trajectory images available for verification")
        else:
            vlm_response = query_vlm(
                prompt=VERIFICATION_PROMPT,
                images=images
            )
            
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if isinstance(parsed, str):
                    try:
                        parsed = json.loads(parsed)
                    except:
                        parsed = {}
                
                vlm_metrics["building_created"] = parsed.get("building_created", False)
                vlm_metrics["skelion_used"] = parsed.get("skelion_used", False)
                vlm_metrics["panels_on_vertical_wall"] = parsed.get("panels_on_vertical_wall", False)
                vlm_metrics["grid_arrangement"] = parsed.get("grid_arrangement", False)
                vlm_metrics["location_set"] = parsed.get("location_set", False)
                
                logger.info(f"VLM reasoning: {parsed.get('reasoning', 'No reasoning provided')}")
            else:
                feedback_parts.append("❌ VLM query failed")

    # Score VLM criteria
    if vlm_metrics["building_created"]:
        score += 15
        feedback_parts.append("✅ Building modeled (+15)")
    else:
        feedback_parts.append("❌ Building geometry not detected")

    if vlm_metrics["skelion_used"]:
        score += 15
        feedback_parts.append("✅ Skelion plugin interaction detected (+15)")
    else:
        feedback_parts.append("❌ Skelion usage not detected")

    if vlm_metrics["panels_on_vertical_wall"]:
        score += 30
        feedback_parts.append("✅ Solar panels placed on vertical façade (+30)")
    else:
        feedback_parts.append("❌ Panels NOT found on vertical wall (Core Task Failure)")

    if vlm_metrics["grid_arrangement"]:
        score += 10
        feedback_parts.append("✅ Panel grid arrangement verified (+10)")

    if vlm_metrics["location_set"]:
        score += 10
        feedback_parts.append("✅ Location settings accessed (+10)")

    # 3. Determine Final Pass/Fail
    # To pass, the file must exist, score >= 60, AND panels must be on the vertical wall
    key_criteria_met = output_exists and vlm_metrics["panels_on_vertical_wall"]
    passed = (score >= 60) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "file_size": file_size,
            "vlm_metrics": vlm_metrics
        }
    }