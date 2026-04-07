#!/usr/bin/env python3
import json
import os
import base64
import re
import math
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_measured_mile_world_creation(traj, env_info, task_info):
    """
    Verifies the Measured Mile World Creation task.
    
    Criteria:
    1. World & Scenario Directories exist (20 pts)
    2. Assets (PNGs) are valid and 1024x1024 (20 pts)
    3. Configuration logic (terrain.ini maps textures) (10 pts)
    4. Geodetic Precision (buoy.ini coordinates) (40 pts)
       - 1 NM distance check (+/- 5%)
    5. Scenario configuration (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Structure Check (20 pts)
    if result.get("world_dir_exists"):
        score += 10
        feedback.append("World directory created.")
    else:
        feedback.append("World directory missing.")
        
    if result.get("scenario_dir_exists"):
        score += 10
        feedback.append("Scenario directory created.")
    else:
        feedback.append("Scenario directory missing.")

    # 2. Assets Check (20 pts)
    files = result.get("files", {})
    dims = result.get("image_dims", {})
    
    # Heightmap
    h_dim = dims.get("height", [0,0])
    if files.get("height_png") == "true" and h_dim == [1024, 1024]:
        score += 10
        feedback.append("Heightmap created correctly (1024x1024).")
    else:
        feedback.append(f"Heightmap invalid or missing (Dims: {h_dim}).")

    # Texture
    t_dim = dims.get("texture", [0,0])
    if files.get("texture_png") == "true" and t_dim == [1024, 1024]:
        score += 10
        feedback.append("Texture created correctly (1024x1024).")
    else:
        feedback.append(f"Texture invalid or missing (Dims: {t_dim}).")

    # 3. Config Logic (10 pts)
    # Check terrain.ini maps to the files
    try:
        terrain_content = base64.b64decode(result["content_base64"]["terrain_ini"]).decode('utf-8', errors='ignore')
        if "height.png" in terrain_content and "texture.png" in terrain_content:
            score += 10
            feedback.append("terrain.ini correctly maps assets.")
        else:
            feedback.append("terrain.ini does not reference height.png or texture.png.")
    except Exception:
        feedback.append("terrain.ini missing or unreadable.")

    # 4. Geodetic Precision (40 pts)
    # This is the core skill check
    buoy_score = 0
    try:
        buoy_content = base64.b64decode(result["content_base64"]["buoy_ini"]).decode('utf-8', errors='ignore')
        
        # Parse buoys using regex (Bridge Command uses Lat(N)=X format)
        # Find all Lat(N)=val and Long(N)=val
        lats = [float(x) for x in re.findall(r'Lat\(\d+\)=([0-9.-]+)', buoy_content, re.IGNORECASE)]
        
        if len(lats) == 4:
            min_lat = min(lats)
            max_lat = max(lats)
            delta_lat = max_lat - min_lat
            
            # Expected delta: 1 minute = 1/60 degrees ~= 0.016667
            target_delta = 1.0 / 60.0
            error = abs(delta_lat - target_delta)
            
            # Tolerance: 0.05 NM = 0.05 minutes = 0.05/60 degrees ~= 0.00083
            tolerance = 0.05 / 60.0
            
            nm_measured = delta_lat * 60.0
            
            if error < tolerance:
                buoy_score += 40
                feedback.append(f"Measured Mile precision PERFECT. Distance: {nm_measured:.4f} NM.")
            elif error < (tolerance * 2):
                buoy_score += 20
                feedback.append(f"Measured Mile precision ACCEPTABLE. Distance: {nm_measured:.4f} NM.")
            else:
                feedback.append(f"Measured Mile OUT OF TOLERANCE. Distance: {nm_measured:.4f} NM (Target: 1.0).")
        else:
            feedback.append(f"Found {len(lats)} markers, expected 4.")
            
    except Exception as e:
        feedback.append(f"Error parsing buoy.ini: {e}")
    
    score += buoy_score

    # 5. Scenario Config (10 pts)
    try:
        env_content = base64.b64decode(result["content_base64"]["env_ini"]).decode('utf-8', errors='ignore')
        if 'Setting="MeasuredMile"' in env_content or 'Setting=MeasuredMile' in env_content:
            score += 10
            feedback.append("Scenario correctly references new world.")
        else:
            feedback.append("Scenario environment.ini does not reference 'MeasuredMile'.")
    except:
        pass

    passed = (score >= 70) and (buoy_score > 0)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }