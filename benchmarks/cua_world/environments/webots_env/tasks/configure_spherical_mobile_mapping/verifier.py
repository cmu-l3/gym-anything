#!/usr/bin/env python3
"""
Verifier for configure_spherical_mobile_mapping task.

GIS/AV Engineer must configure a simulated mobile mapping payload.
Requires parsing the saved .wbt file to ensure properties exactly match the prompt.

Scoring (100 points total):
  - File saved at correct path & created during task: 10 points
  - WGS84 configured (gpsCoordinateSystem and gpsReference): 20 points
  - Camera Projection (spherical) & FOV (6.28318): 20 points
  - Camera Resolution (4096 x 2048): 15 points
  - LiDAR layers (64) & horizontal resolution (2048): 20 points
  - LiDAR FOV (6.28318): 15 points

Pass threshold: 70 points
VLM Trajectory verification ensures the agent actively used the UI.
"""

import json
import re
import tempfile
import os
import logging
import math

logger = logging.getLogger(__name__)

def verify_spherical_mobile_mapping(traj, env_info, task_info):
    """
    Verify that the mobile mapping world was configured properly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/spherical_mapping.wbt')
    
    score = 0
    feedback_parts = []

    # --- Step 1: Parse Result JSON ---
    try:
        result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        result_file.close()
        copy_from_env('/tmp/task_result.json', result_file.name)
        with open(result_file.name) as f:
            export_result = json.load(f)
        os.unlink(result_file.name)
    except Exception as e:
        logger.warning(f"Could not read task_result.json: {e}")
        export_result = {}

    file_exists = export_result.get('file_exists', False)
    file_created = export_result.get('file_created_during_task', False)

    if not file_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}. You must save the world via File > Save World As."
        }

    if file_created:
        score += 10
        feedback_parts.append("World file properly saved")
    else:
        feedback_parts.append("World file exists but timestamp indicates it was not saved during this task")

    # --- Step 2: Copy the .wbt file independently ---
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

    if not wbt_content or len(wbt_content) < 100:
        return {"passed": False, "score": score, "feedback": "World file is empty or corrupted."}

    # --- Step 3: Check WorldInfo (WGS84 & San Francisco coords) ---
    coord_system_match = re.search(r'gpsCoordinateSystem\s+"([^"]+)"', wbt_content)
    gps_ref_match = re.search(r'gpsReference\s+([\d.-]+)\s+([\d.-]+)\s+([\d.-]+)', wbt_content)
    
    wgs84_correct = False
    ref_correct = False
    
    if coord_system_match and coord_system_match.group(1) == "WGS84":
        wgs84_correct = True
    
    if gps_ref_match:
        lat, lon, alt = map(float, gps_ref_match.groups())
        if abs(lat - 37.7749) < 0.01 and abs(lon - (-122.4194)) < 0.01 and abs(alt - 15.0) < 0.1:
            ref_correct = True

    if wgs84_correct and ref_correct:
        score += 20
        feedback_parts.append("WorldInfo GPS configured to WGS84 for San Francisco")
    else:
        feedback_parts.append(f"WorldInfo GPS setup incorrect. WGS84={wgs84_correct}, RefCorrect={ref_correct}")

    # --- Step 4: Extract Node Segments ---
    # Finding node chunks to prevent false positive regex matches across different nodes
    camera_idx = wbt_content.find('name "pano_camera"')
    if camera_idx == -1: camera_idx = wbt_content.find('DEF pano_camera Camera')
    
    lidar_idx = wbt_content.find('name "roof_lidar"')
    if lidar_idx == -1: lidar_idx = wbt_content.find('DEF roof_lidar Lidar')

    if camera_idx != -1:
        camera_segment = wbt_content[max(0, camera_idx-200):camera_idx+400]
    else:
        camera_segment = ""

    if lidar_idx != -1:
        lidar_segment = wbt_content[max(0, lidar_idx-200):lidar_idx+400]
    else:
        lidar_segment = ""

    # --- Step 5: Check pano_camera properties ---
    cam_proj = re.search(r'projection\s+"([^"]+)"', camera_segment)
    cam_fov = re.search(r'fieldOfView\s+([\d.]+)', camera_segment)
    cam_width = re.search(r'width\s+(\d+)', camera_segment)
    cam_height = re.search(r'height\s+(\d+)', camera_segment)

    if cam_proj and cam_proj.group(1) == "spherical":
        if cam_fov and abs(float(cam_fov.group(1)) - 6.28318) < 0.05:
            score += 20
            feedback_parts.append("Camera uses spherical 360 projection")
        else:
            feedback_parts.append("Camera projection is spherical but FOV is not ~6.28")
    else:
        feedback_parts.append("Camera projection is NOT spherical")

    if cam_width and int(cam_width.group(1)) == 4096 and cam_height and int(cam_height.group(1)) == 2048:
        score += 15
        feedback_parts.append("Camera resolution correctly set to 4096x2048")
    else:
        feedback_parts.append("Camera resolution is incorrect (expected 4096x2048)")

    # --- Step 6: Check roof_lidar properties ---
    lidar_layers = re.search(r'numberOfLayers\s+(\d+)', lidar_segment)
    lidar_res = re.search(r'horizontalResolution\s+(\d+)', lidar_segment)
    lidar_fov = re.search(r'fieldOfView\s+([\d.]+)', lidar_segment)

    if lidar_layers and int(lidar_layers.group(1)) == 64 and lidar_res and int(lidar_res.group(1)) == 2048:
        score += 20
        feedback_parts.append("LiDAR layers and horizontal resolution match HDL-64E")
    else:
        feedback_parts.append("LiDAR layers/resolution incorrect (expected 64 layers, 2048 res)")

    if lidar_fov and abs(float(lidar_fov.group(1)) - 6.28318) < 0.05:
        score += 15
        feedback_parts.append("LiDAR FOV is full 360 degrees")
    else:
        feedback_parts.append("LiDAR FOV is incorrect (expected ~6.28)")

    # --- Step 7: VLM Trajectory Verification ---
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        prompt = """Look at these screenshots from an agent's desktop session using the Webots 3D Simulator.
Did the agent actively use the Webots user interface (specifically the scene tree on the left side) to edit properties of nodes such as WorldInfo, Camera, or Lidar?
Reply ONLY with a JSON dictionary in this exact format: {"used_ui": true/false}"""
        vlm_res = query_vlm(images=frames, prompt=prompt)
        if vlm_res and vlm_res.get('success'):
            try:
                parsed = vlm_res.get('parsed', {})
                if parsed.get('used_ui', False):
                    feedback_parts.append("VLM confirms UI manipulation")
                else:
                    feedback_parts.append("VLM did not observe active UI manipulation (possible terminal spoofing)")
            except Exception as e:
                logger.warning(f"VLM JSON parsing error: {e}")
    else:
        logger.warning("No trajectory frames available for VLM check.")

    passed = score >= 70 and wgs84_correct and (cam_proj and cam_proj.group(1) == "spherical")

    if passed and score < 100:
        feedback_parts.append("Passed with partial configuration.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }