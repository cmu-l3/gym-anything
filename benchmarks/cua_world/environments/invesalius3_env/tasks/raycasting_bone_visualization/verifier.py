#!/usr/bin/env python3
"""
Verifier for raycasting_bone_visualization task.

VERIFICATION STRATEGY:
1. File Verification (40 pts):
   - Output PNG exists and is valid
   - File size > 100KB (ensures non-trivial content)
   - Created during task session

2. VLM Verification (60 pts):
   - Checks if image shows a 3D Volume Rendering (not surface mesh/2D slices)
   - Checks if bone/skull structure is visible

PASS THRESHOLD: 60 points + VLM Confirmation
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_raycasting_bone(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load File-based Results
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
    feedback_parts = []
    
    # --- Criterion 1: File Existence & Validity (40 pts total) ---
    output_exists = result.get("output_exists", False)
    is_valid_png = result.get("is_valid_png", False)
    file_size_kb = result.get("file_size_bytes", 0) / 1024
    created_during = result.get("file_created_during_task", False)
    
    if output_exists and is_valid_png:
        score += 10
        feedback_parts.append("Valid PNG file found")
        
        if created_during:
            score += 10
            feedback_parts.append("File created during task")
        else:
            feedback_parts.append("WARNING: File timestamp predates task")
            
        if file_size_kb > 100:
            score += 20
            feedback_parts.append(f"File size OK ({file_size_kb:.1f} KB)")
        else:
            feedback_parts.append(f"File too small ({file_size_kb:.1f} KB) - likely empty/black")
    else:
        feedback_parts.append("Output file missing or invalid")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # --- Criterion 2: VLM Visual Verification (60 pts) ---
    # We analyze the exported image if available, otherwise the final screenshot
    
    # Ideally, we verify the exported file itself. Since we can't easily "download" it 
    # to the verifier environment without a custom tool, we rely on the framework's 
    # screenshot capability or assume the 'final_screenshot' captures the app state 
    # if the file verification passed.
    # HOWEVER, a strong verification should check the ACTUAL exported content.
    # Strategy: If the user opened the image or if it's visible on screen, fine.
    # But usually, we rely on the task's final screenshot to verify the APP STATE 
    # showed the volume rendering before export.
    
    final_screenshot = get_final_screenshot(traj)
    if not final_screenshot:
        feedback_parts.append("No screenshot available for VLM verification")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    prompt = """
    You are evaluating a task in InVesalius 3 medical software. 
    The user was asked to enable "Raycasting" (Volume Rendering) for a skull CT scan.
    
    Analyze the image. Look for a 3D view panel (usually bottom right or large window).
    
    1. Is there a 3D visualization of a skull/cranium visible?
    2. Is it a VOLUME RENDERING (Raycasting)? 
       - Volume rendering often looks semi-transparent, foggy, or has gradient shading.
       - Surface rendering (mesh) looks like a hard, solid plastic shell, often single-color.
    3. Are bone structures clearly visible?
    
    Respond in JSON:
    {
        "skull_visible": true/false,
        "is_volume_rendering": true/false,
        "is_surface_rendering": true/false,
        "confidence": "high/medium/low"
    }
    """
    
    vlm_result = query_vlm(image=final_screenshot, prompt=prompt)
    
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        skull_visible = parsed.get("skull_visible", False)
        is_volume_rendering = parsed.get("is_volume_rendering", False)
        is_surface_rendering = parsed.get("is_surface_rendering", False)
        
        if skull_visible:
            if is_volume_rendering:
                score += 60
                feedback_parts.append("VLM confirmed: 3D Volume Rendering of skull visible")
            elif is_surface_rendering:
                score += 20
                feedback_parts.append("VLM detected Surface Rendering (Mesh) instead of Volume Rendering (Raycasting)")
            else:
                score += 10
                feedback_parts.append("VLM detected skull but unclear rendering type")
        else:
            feedback_parts.append("VLM did not detect a 3D skull visualization")
    else:
        feedback_parts.append("VLM verification failed to execute")

    passed = score >= 70  # Needs decent file + correct visual type
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }