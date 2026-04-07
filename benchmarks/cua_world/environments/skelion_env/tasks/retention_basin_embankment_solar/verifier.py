#!/usr/bin/env python3
"""
Verifier for retention_basin_embankment_solar task.

Uses a hybrid approach:
1. File verification (existence, size, modification timestamp to prevent gaming).
2. Trajectory-based VLM verification to confirm 3D spatial properties (basin 
   depression geometry, panel layout, and flush mount characteristics) since 
   direct geometric inspection via SketchUp's Ruby API can be flaky during headless automation.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are verifying if a computer agent successfully modeled a solar installation on a retention basin embankment in SketchUp.

TASK GOAL: Model a sunken stormwater retention basin with sloped embankments, and place flush-mounted solar panels on the south-facing interior slope.

Look at these screenshots from the agent's workflow and final state. Evaluate the following criteria:

1. Basin Geometry: Is there a visible sunken geometric basin/depression? (Look for sloped interior walls going down, forming a pit or basin, not a solid raised extruded box).
2. Panel Presence: Are there solar panels (typically blue/dark rectangular grid patterns) visible in the model?
3. Array Placement: Are the solar panels placed on one of the sloped interior embankments of the basin?
4. Flush Mount: Are the panels flush (parallel) to the sloped earth surface, rather than being mounted on raised, independently tilted racks?

Respond exactly in JSON format:
{
    "basin_geometry_visible": true/false,
    "panel_presence_visible": true/false,
    "array_placement_correct": true/false,
    "flush_mount_visible": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation of your visual findings"
}
"""

def verify_retention_basin_embankment_solar(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # File Checks
    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    output_size = result.get('output_size_bytes', 0)
    
    score = 0
    feedback_parts = []
    
    if output_exists:
        score += 10
        feedback_parts.append("File exists")
        
        if file_created:
            score += 10
            feedback_parts.append("File created during task")
        else:
            feedback_parts.append("FAIL: File NOT modified during task (anti-gaming)")
            
        # A basic SketchUp file is ~15-20KB. With a large basin and dozens of components, it should be >50KB
        if output_size > 50000:
            score += 10
            feedback_parts.append(f"File size robust ({output_size//1024}KB)")
        else:
            feedback_parts.append(f"File size too small ({output_size//1024}KB) - missing components?")
    else:
        feedback_parts.append("Output file NOT found")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }
        
    # VLM Verification based on Trajectory Frames
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            vlm_result = query_vlm(images=images, prompt=VERIFICATION_PROMPT)
            
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                basin_geom = parsed.get("basin_geometry_visible", False)
                panels = parsed.get("panel_presence_visible", False)
                placement = parsed.get("array_placement_correct", False)
                flush = parsed.get("flush_mount_visible", False)
                
                if basin_geom:
                    score += 20
                    feedback_parts.append("VLM: Basin geometry confirmed")
                else:
                    feedback_parts.append("VLM: Basin geometry missing")
                    
                if panels:
                    score += 10
                    feedback_parts.append("VLM: Panels detected")
                else:
                    feedback_parts.append("VLM: Panels missing")
                    
                if placement:
                    score += 20
                    feedback_parts.append("VLM: Slope placement correct")
                else:
                    feedback_parts.append("VLM: Slope placement incorrect")
                    
                if flush:
                    score += 20
                    feedback_parts.append("VLM: Flush mount confirmed")
                else:
                    feedback_parts.append("VLM: Flush mount missing")
            else:
                feedback_parts.append("VLM query processing failed")
        else:
            feedback_parts.append("VLM query function not accessible")
    except ImportError:
        feedback_parts.append("gym_anything.vlm import failed")
        
    # Final Evaluation (Must pass geometric thresholds AND have actually created the file during runtime)
    key_criteria_met = output_exists and file_created and score >= 70
    
    return {
        "passed": key_criteria_met,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }