#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_molecular_viz(traj, env_info, task_info):
    """
    Verify molecular visualization task.
    
    Criteria:
    1. Add-on enabled (10 pts)
    2. Import successful (Object count > 10) (30 pts)
    3. Carbon Material Style (Black, Matte) (20 pts)
    4. Oxygen Material Style (Red, Glowing) (20 pts)
    5. Render & Save (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    scene = data.get("scene_analysis", {})
    materials = scene.get("materials", {})
    
    # 1. Add-on check (10 pts)
    if scene.get("addon_enabled"):
        score += 10
        feedback.append("Atomic Blender add-on enabled.")
    else:
        feedback.append("Atomic Blender add-on NOT enabled (or detected).")

    # 2. Import check (30 pts)
    # Caffeine has >10 atoms. Default scene has ~3 objects.
    obj_count = scene.get("object_count", 0)
    if obj_count > 10:
        score += 30
        feedback.append(f"Molecule imported (Object count: {obj_count}).")
    else:
        feedback.append(f"Import failed or too few objects ({obj_count}).")

    # 3. Carbon Style (20 pts)
    # Look for material with 'Carbon' or 'C' in name
    carbon_found = False
    for name, mat in materials.items():
        if "Carbon" in name or "Carbon" in name: # "Carbon" is standard Atomic Blender name
            carbon_found = True
            # Check Black (Value < 0.1)
            color = mat.get("base_color", [1,1,1,1])
            avg_val = sum(color[:3])/3
            
            # Check Roughness (> 0.8)
            roughness = mat.get("roughness", 0.0)
            
            if avg_val < 0.2 and roughness > 0.8:
                score += 20
                feedback.append("Carbon material styled correctly (Matte Black).")
            else:
                score += 5 # Partial credit for finding it
                feedback.append(f"Carbon material found but style incorrect (Val: {avg_val:.2f}, Rough: {roughness:.2f}).")
            break
    
    if not carbon_found:
        feedback.append("Carbon material not found.")

    # 4. Oxygen Style (20 pts)
    # Look for 'Oxygen' or 'O'
    oxygen_found = False
    for name, mat in materials.items():
        if "Oxygen" in name:
            oxygen_found = True
            # Check Red (R > G+B)
            color = mat.get("base_color", [1,1,1,1])
            is_red = color[0] > (color[1] + color[2])
            
            # Check Emission (> 4.0)
            emission = mat.get("emission_strength", 0.0)
            
            if is_red and emission >= 4.0:
                score += 20
                feedback.append("Oxygen material styled correctly (Glowing Red).")
            elif is_red:
                score += 10
                feedback.append("Oxygen is red but not glowing enough.")
            else:
                score += 5
                feedback.append("Oxygen found but style incorrect.")
            break
            
    if not oxygen_found:
        feedback.append("Oxygen material not found.")

    # 5. Output Files (20 pts)
    if data.get("blend_exists"):
        score += 10
        feedback.append("Blend file saved.")
    if data.get("render_exists") and data.get("render_size", 0) > 50000: # >50KB
        score += 10
        feedback.append("Render output created.")
    
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }