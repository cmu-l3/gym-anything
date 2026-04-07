#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_build_navigation_arena(traj, env_info, task_info):
    """
    Verify that the user correctly assembled the navigation benchmark arena 
    with the 4 pillars, lidar settings, title, and controller.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Read task result metadata (for anti-gaming checks)
    result_json = {}
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            result_json = json.load(f)
    except Exception as e:
        logger.error(f"Could not read task_result.json: {e}")
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)
            
    # 2. Read WBT file content
    wbt_content = ""
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    try:
        copy_from_env("/home/ga/Desktop/navigation_benchmark.wbt", wbt_file.name)
        with open(wbt_file.name, 'r', errors='replace') as f:
            wbt_content = f.read()
    except Exception as e:
        logger.warning(f"Could not copy or read output wbt: {e}")
    finally:
        if os.path.exists(wbt_file.name):
            os.unlink(wbt_file.name)

    score = 0
    feedback_parts = []
    
    # Base existence checks
    output_exists = result_json.get('output_exists', False)
    file_size = result_json.get('output_size_bytes', 0)
    
    if output_exists:
        score += 5
        feedback_parts.append("File exists")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found at /home/ga/Desktop/navigation_benchmark.wbt"}
        
    if file_size > 500:
        score += 5
        feedback_parts.append("File valid (>500 bytes)")
    else:
        feedback_parts.append("File too small/invalid")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    # Pillar parsing
    expected_pillars = {
        1: (1.0, 1.0),
        2: (-1.0, 1.0),
        3: (1.0, -1.0),
        4: (-1.0, -1.0)
    }
    
    for pid, (ex, ez) in expected_pillars.items():
        # Match PILLAR_n and its following translation
        idx = wbt_content.find(f'PILLAR_{pid}')
        if idx != -1:
            segment = wbt_content[idx:idx+400]
            t_match = re.search(r'translation\s+([\d.-]+)\s+([\d.-]+)\s+([\d.-]+)', segment)
            if t_match:
                px, py, pz = float(t_match.group(1)), float(t_match.group(2)), float(t_match.group(3))
                if abs(px - ex) <= 0.3 and abs(pz - ez) <= 0.3:
                    score += 10
                    feedback_parts.append(f"PILLAR_{pid} at correct location")
                else:
                    feedback_parts.append(f"PILLAR_{pid} at wrong location ({px}, {pz})")
            else:
                feedback_parts.append(f"PILLAR_{pid} translation not found")
        else:
            feedback_parts.append(f"PILLAR_{pid} not found")
            
    # Geometry and Physics checks
    cylinder_count = len(re.findall(r'Cylinder\s*\{', wbt_content))
    if cylinder_count >= 3:
        score += 5
        feedback_parts.append("Cylinder geometries found")
    else:
        feedback_parts.append("Cylinder geometries missing")
        
    physics_count = len(re.findall(r'Physics\s*\{', wbt_content))
    if physics_count >= 3:
        score += 5
        feedback_parts.append("Physics nodes found")
    else:
        feedback_parts.append("Physics nodes missing")

    # Lidar configuration
    layers_match = re.search(r'numberOfLayers\s+(\d+)', wbt_content)
    if layers_match and int(layers_match.group(1)) == 4:
        score += 10
        feedback_parts.append("LIDAR layers=4")
    else:
        feedback_parts.append("LIDAR layers incorrect")
        
    range_match = re.search(r'maxRange\s+([\d.]+)', wbt_content)
    if range_match and 4.5 <= float(range_match.group(1)) <= 5.5:
        score += 5
        feedback_parts.append("LIDAR maxRange=5.0")
    else:
        feedback_parts.append("LIDAR maxRange incorrect")

    fov_match = re.search(r'fieldOfView\s+([\d.]+)', wbt_content)
    if fov_match and 2.8 <= float(fov_match.group(1)) <= 3.5:
        score += 5
        feedback_parts.append("LIDAR FOV correct")
    else:
        feedback_parts.append("LIDAR FOV incorrect")

    res_match = re.search(r'horizontalResolution\s+(\d+)', wbt_content)
    if res_match and int(res_match.group(1)) == 360:
        score += 5
        feedback_parts.append("LIDAR horizontalResolution=360")
    else:
        feedback_parts.append("LIDAR horizontalResolution incorrect")

    # Title & Controller
    title_match = re.search(r'title\s+"([^"]+)"', wbt_content)
    if title_match and "Navigation Benchmark" in title_match.group(1):
        score += 5
        feedback_parts.append("Title correct")
    else:
        feedback_parts.append("Title incorrect")
        
    if re.search(r'controller\s+"void"', wbt_content):
        score += 10
        feedback_parts.append("Controller set to void")
    else:
        feedback_parts.append("Controller not set to void")

    # Anti-gaming checks
    file_created_during_task = result_json.get('file_created_during_task', False)
    if not file_created_during_task:
        feedback_parts.append("File timestamp indicates it was not created/modified during task.")
        
    passed = score >= 65 and file_created_during_task
        
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }