#!/usr/bin/env python3
"""
Verifier for physical_sky_reference_spheres task.
"""

import json
import math
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_physical_sky_setup(traj, env_info, task_info):
    """
    Verify the Blender physical sky and reference spheres task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. Verify World/Sky Setup (30 points)
    scene_data = result.get('scene_analysis', {})
    world_data = scene_data.get('world', {})
    
    if world_data.get('has_sky') and world_data.get('sky_type') == 'NISHITA':
        score += 20
        feedback.append("World Shader: Nishita Sky Texture configured correctly (+20)")
        
        # Check Sun Elevation (Golden Hour: ~10-35 degrees)
        elevation_rad = world_data.get('sun_elevation', 0)
        elevation_deg = math.degrees(elevation_rad)
        
        target_min = task_info['metadata'].get('target_sun_elevation_min_deg', 10)
        target_max = task_info['metadata'].get('target_sun_elevation_max_deg', 35)
        
        if target_min <= elevation_deg <= target_max:
            score += 10
            feedback.append(f"Sun Elevation: Correct golden hour angle ({elevation_deg:.1f}°) (+10)")
        else:
            feedback.append(f"Sun Elevation: Angle {elevation_deg:.1f}° outside golden hour range ({target_min}-{target_max}°)")
    else:
        feedback.append("World Shader: Nishita Sky Texture NOT found")

    # 2. Verify Reference Spheres (40 points)
    objects = scene_data.get('objects', [])
    chrome_found = False
    matte_found = False
    
    chrome_target = task_info['metadata'].get('chrome_location', [-2, 0, 1])
    matte_target = task_info['metadata'].get('matte_location', [2, 0, 1])
    tolerance = task_info['metadata'].get('location_tolerance', 1.5)
    
    for obj in objects:
        loc = obj['location']
        mats = obj.get('materials', [])
        if not mats: continue
        mat = mats[0]
        
        # Distance checks
        dist_chrome = math.sqrt(sum((a-b)**2 for a,b in zip(loc, chrome_target)))
        dist_matte = math.sqrt(sum((a-b)**2 for a,b in zip(loc, matte_target)))
        
        # Check properties
        # Chrome: High Metallic, Low Roughness
        is_chrome = (mat['metallic'] > 0.8 and mat['roughness'] < 0.1)
        # Matte: Low Metallic, High Roughness
        is_matte = (mat['metallic'] < 0.2 and mat['roughness'] > 0.8)
        
        if is_chrome and dist_chrome < tolerance:
            chrome_found = True
        if is_matte and dist_matte < tolerance:
            matte_found = True

    if chrome_found:
        score += 20
        feedback.append("Chrome Sphere: Found with correct material and location (+20)")
    else:
        feedback.append("Chrome Sphere: Not found or incorrect material/location")
        
    if matte_found:
        score += 20
        feedback.append("Matte Sphere: Found with correct material and location (+20)")
    else:
        feedback.append("Matte Sphere: Not found or incorrect material/location")

    # 3. Verify Render Output (20 points)
    if result.get('render_exists') and result.get('render_size_kb', 0) > 50:
        score += 20
        feedback.append("Render: Output file exists and valid size (+20)")
    else:
        feedback.append("Render: Output file missing or empty")

    # 4. VLM Verification (10 points - Bonus/Confirmation)
    # Check the final screenshot for visual confirmation of sky and two spheres
    if query_vlm:
        # We need the task's final screenshot path relative to where verifier runs
        # Ideally, we pass the image content or path. 
        # Since we rely on the framework, we look at the last frame or a specific screenshot if provided.
        # Here we assume the framework handles image passing or we skip if unavailable.
        pass # Placeholder for VLM logic if framework supports direct image passing in verifier signature

    # 5. File Saved Check (10 points)
    if result.get('blend_exists'):
        score += 10
        feedback.append("Project: .blend file saved (+10)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }