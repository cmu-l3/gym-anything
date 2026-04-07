#!/usr/bin/env python3
"""
Verifier for configure_adverse_weather_scene task.

HYBRID VERIFICATION:
1. Programmatic: Parses the output .wbt file to ensure exact environmental physics nodes
   (Fog, DirectionalLight, Background, Camera) match perception testing spec.
2. Anti-Gaming: Checks file timestamps and structural integrity.
3. VLM: Confirms visual workflow progression (trajectory frames).

Scoring (100 points total):
  - File exists and valid creation time: 5 pts
  - Fog node added at scene level: 15 pts
  - Fog visibilityRange ≈ 50: 10 pts
  - Fog fogType = EXPONENTIAL: 5 pts
  - DirectionalLight intensity modified to ~0.4: 15 pts
  - DirectionalLight color warm/amber: 15 pts
  - Background skyColor overcast: 15 pts
  - Camera far clipping plane extended >= 60.0: 15 pts
  - Structural Integrity (Robot node untouched): 5 pts

Pass threshold: 70 points
"""

import json
import re
import tempfile
import os
import logging
import math

# Try to import gym_anything VLM utilities
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logger = logging.getLogger(__name__)


def extract_node_block(content, node_name):
    """Extract a complete node block from the .wbt content."""
    matches = list(re.finditer(rf'\b{node_name}\s*{{', content))
    if not matches:
        return None
        
    start_idx = matches[0].start()
    depth = 0
    for i in range(start_idx, len(content)):
        if content[i] == '{':
            depth += 1
        elif content[i] == '}':
            depth -= 1
            if depth == 0:
                return content[start_idx:i+1]
                
    return content[start_idx:]


def verify_configure_adverse_weather_scene(traj, env_info, task_info):
    """
    Verify the environmental physics parameters were updated to adverse weather specs.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/adverse_weather.wbt')

    score = 0
    feedback_parts = []
    
    # --- Check metadata JSON for anti-gaming ---
    meta_result = {}
    try:
        temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_json.close()
        copy_from_env('/tmp/task_result.json', temp_json.name)
        with open(temp_json.name) as f:
            meta_result = json.load(f)
        os.unlink(temp_json.name)
    except Exception:
        pass

    # --- Copy the .wbt file ---
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_file.close()
    wbt_content = None

    try:
        copy_from_env(output_path, wbt_file.name)
        with open(wbt_file.name, 'r', errors='replace') as f:
            wbt_content = f.read()
        os.unlink(wbt_file.name)
    except Exception as e:
        logger.warning(f"Could not copy .wbt file: {e}")
        try:
            os.unlink(wbt_file.name)
        except Exception:
            pass

    # --- 1. File Existence & Integrity (10 pts) ---
    if not wbt_content or len(wbt_content) < 300:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path} or is corrupted."
        }
        
    if not meta_result.get('file_created_during_task', True):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Anti-gaming: Output file was modified before task started."
        }

    score += 5
    feedback_parts.append("File exists and timestamp is valid")

    # Integrity check
    if "DEF FIELD_ROBOT" in wbt_content and "WorldInfo" in wbt_content:
        score += 5
        feedback_parts.append("File structural integrity maintained")
    else:
        feedback_parts.append("Warning: Missing expected Robot or WorldInfo nodes")

    # --- 2. Fog Configuration (30 pts) ---
    fog_block = extract_node_block(wbt_content, 'Fog')
    if fog_block:
        score += 15
        feedback_parts.append("Fog node found")
        
        # Check visibilityRange (target 50.0)
        vis_match = re.search(r'visibilityRange\s+([\d.]+)', fog_block)
        if vis_match:
            vis_val = float(vis_match.group(1))
            if 40.0 <= vis_val <= 60.0:
                score += 10
                feedback_parts.append(f"Fog visibilityRange correct: {vis_val}")
            else:
                feedback_parts.append(f"Fog visibilityRange {vis_val} outside acceptable range (40-60)")
        else:
            feedback_parts.append("Fog visibilityRange field not found")
            
        # Check fogType (target "EXPONENTIAL")
        type_match = re.search(r'fogType\s+"([^"]+)"', fog_block)
        if type_match and "EXPONENTIAL" in type_match.group(1).upper():
            score += 5
            feedback_parts.append("Fog fogType EXPONENTIAL correct")
        else:
            feedback_parts.append("Fog fogType should be EXPONENTIAL")
    else:
        feedback_parts.append("Fog node not found in scene")

    # --- 3. DirectionalLight Configuration (30 pts) ---
    light_block = extract_node_block(wbt_content, 'DirectionalLight')
    if light_block:
        # Check intensity (target 0.4)
        int_match = re.search(r'intensity\s+([\d.]+)', light_block)
        if int_match:
            intensity = float(int_match.group(1))
            if 0.25 <= intensity <= 0.55:
                score += 15
                feedback_parts.append(f"DirectionalLight intensity correct: {intensity}")
            else:
                feedback_parts.append(f"DirectionalLight intensity {intensity} outside expected range (~0.4)")
        
        # Check color (target 1 0.9 0.7)
        col_match = re.search(r'color\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)', light_block)
        if col_match:
            r, g, b = float(col_match.group(1)), float(col_match.group(2)), float(col_match.group(3))
            # Warm color: R high, G slightly lower, B lower
            if r >= 0.9 and g <= 0.95 and b <= 0.8:
                score += 15
                feedback_parts.append("DirectionalLight color matches amber/warm profile")
            else:
                feedback_parts.append(f"DirectionalLight color [{r} {g} {b}] not warm enough")
    else:
        feedback_parts.append("DirectionalLight node missing")

    # --- 4. Background Configuration (15 pts) ---
    bg_block = extract_node_block(wbt_content, 'Background')
    if bg_block:
        # Check skyColor (target 0.4 0.5 0.6 overcast)
        sky_match = re.search(r'skyColor\s*\[\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)\s*\]', bg_block)
        if sky_match:
            r, g, b = float(sky_match.group(1)), float(sky_match.group(2)), float(sky_match.group(3))
            if r < 0.7 and g < 0.7 and b < 0.7:  # Darker greyish
                score += 15
                feedback_parts.append("Background skyColor matches overcast profile")
            else:
                feedback_parts.append(f"Background skyColor [{r} {g} {b}] not overcast")
    else:
        feedback_parts.append("Background node missing")

    # --- 5. Camera Far Clipping Plane (15 pts) ---
    # Find perception_camera specifically to avoid false positives
    cam_idx = wbt_content.find('name "perception_camera"')
    if cam_idx != -1:
        # Look around the camera name for the 'far' property
        search_radius = wbt_content[max(0, cam_idx-200):min(len(wbt_content), cam_idx+200)]
        far_match = re.search(r'far\s+([\d.]+)', search_radius)
        if far_match:
            far_val = float(far_match.group(1))
            if far_val >= 60.0:
                score += 15
                feedback_parts.append(f"Camera far clipping plane extended correctly ({far_val})")
            else:
                feedback_parts.append(f"Camera far plane is {far_val}, should be >= 60 to encompass fog")
        else:
            feedback_parts.append("Camera far field not found near perception_camera")
    else:
        feedback_parts.append("perception_camera not found in scene tree")

    # --- Optional Trajectory VLM Verification (Anti-Gaming) ---
    if VLM_AVAILABLE and traj:
        frames = sample_trajectory_frames(traj, n=3)
        if frames:
            prompt = """
            Verify the user's workflow in this 3D Simulator:
            Did the user navigate the scene tree on the left side to add/modify nodes?
            Specifically, did they interact with Background, DirectionalLight, or Fog settings?
            Return JSON: {"workflow_active": true/false}
            """
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res.get("success") and vlm_res.get("parsed", {}).get("workflow_active", False):
                feedback_parts.append("VLM confirmed active scene tree workflow")
            else:
                logger.info("VLM workflow verification failed or inconclusive")

    passed = score >= 70 and ("Fog node found" in feedback_parts)
    
    if not passed and score >= 70:
        feedback_parts.append("FAILED: Core requirement (Fog node addition) missing.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }