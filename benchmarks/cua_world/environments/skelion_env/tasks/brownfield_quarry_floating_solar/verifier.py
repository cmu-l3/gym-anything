#!/usr/bin/env python3
"""
Verifier for brownfield_quarry_floating_solar task.

This task uses a hybrid verification approach:
1. File Verification (30 points): Checks if the .skp file was created during the task and has reasonable size.
2. VLM Verification (70 points): Uses trajectory frames to visually verify the 3D geometry constraints 
   (excavated pit, water texture, floating panels, setbacks, and tilt).
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are an expert 3D modeling and solar engineering evaluator verifying a SketchUp design task.

The user was asked to:
1. Model an excavated quarry pit (a depression in the ground with sloped walls).
2. Add a flat water surface inside the pit (using a blue/water material).
3. Place a floating solar array (PV panels) on the water surface using the Skelion plugin.
4. Ensure the panels have a ~12-degree tilt.
5. Leave a setback/buffer between the solar array and the edges of the water (the shoreline).

Look closely at the provided sequence of screenshots from the agent's session and determine if these criteria were met.

Respond STRICTLY in JSON format with the following keys:
{
    "shows_excavated_pit": true/false,
    "shows_water_surface": true/false,
    "shows_solar_panels": true/false,
    "panels_are_floating": true/false,
    "shows_setback_from_shore": true/false,
    "panels_are_tilted": true/false,
    "reasoning": "Brief explanation of what visual evidence supports your boolean answers."
}

Definitions for your analysis:
- "shows_excavated_pit": Do you see a geometric depression, hole, or pit with sloped banks going downward?
- "shows_water_surface": Is there a surface inside the pit colored blue or textured like water?
- "shows_solar_panels": Are there dark rectangular components representing solar panels?
- "panels_are_floating": Are the panels located ON the water surface inside the pit (not floating in the sky, and not on the top ground plane)?
- "shows_setback_from_shore": Is there empty water space around the perimeter of the solar array before it hits the sloped walls?
- "panels_are_tilted": Do the panels appear to be angled/tilted, casting slight shadows on themselves or looking raised on one edge, rather than lying completely flat (0 degrees) against the water?
"""

def verify_quarry_floating_solar(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}
    if not query_vlm:
        return {"passed": False, "score": 0, "feedback": "System error: query_vlm not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    # ================================================================
    # 1. FILE VERIFICATION
    # ================================================================
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/temp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result JSON: {e}")
        result = {}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    file_size_bytes = result.get('output_size_bytes', 0)

    if not output_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Target file quarry_floating_solar.skp was not saved."
        }

    # Anti-gaming: Ensure it was created/modified during the task
    if file_created_during_task:
        score += 15
        feedback_parts.append("✅ File created/modified during task (+15)")
    else:
        feedback_parts.append("❌ File existed before task and wasn't modified")

    # Size check (a model with geometry and Skelion components should be > 50KB)
    if file_size_bytes >= 50000:
        score += 15
        feedback_parts.append(f"✅ File size valid ({file_size_bytes/1024:.1f} KB) (+15)")
    else:
        feedback_parts.append(f"❌ File too small to contain valid model ({file_size_bytes/1024:.1f} KB)")

    # ================================================================
    # 2. VLM TRAJECTORY VERIFICATION
    # ================================================================
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    if final_frame:
        frames.append(final_frame)
        
    if not frames:
        feedback_parts.append("❌ No trajectory frames available for VLM verification.")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    vlm_result = query_vlm(
        prompt=VERIFICATION_PROMPT,
        images=frames
    )

    if not vlm_result.get("success"):
        feedback_parts.append(f"❌ VLM query failed: {vlm_result.get('error')}")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    parsed = vlm_result.get("parsed", {})
    
    # Evaluate VLM responses
    vlm_criteria = {
        "shows_excavated_pit": {"pts": 15, "desc": "Excavated pit geometry"},
        "shows_water_surface": {"pts": 10, "desc": "Water surface material"},
        "shows_solar_panels": {"pts": 15, "desc": "Solar panels generated"},
        "panels_are_floating": {"pts": 10, "desc": "Panels floating on water"},
        "shows_setback_from_shore": {"pts": 10, "desc": "Setback from shoreline respected"},
        "panels_are_tilted": {"pts": 10, "desc": "Panels are tilted"}
    }
    
    vlm_score = 0
    for key, info in vlm_criteria.items():
        if parsed.get(key, False):
            vlm_score += info["pts"]
            feedback_parts.append(f"✅ {info['desc']} (+{info['pts']})")
        else:
            feedback_parts.append(f"❌ Missing: {info['desc']}")

    score += vlm_score
    
    if "reasoning" in parsed:
        feedback_parts.append(f"VLM Note: {parsed['reasoning']}")

    # Pass condition: File must be created, and must get at least 45 VLM points (meaning pit, water, and panels are present)
    passed = file_created_during_task and (vlm_score >= 45) and (score >= 70)

    return {
        "passed": passed,
        "score": min(score, max_score),
        "feedback": " | ".join(feedback_parts)
    }