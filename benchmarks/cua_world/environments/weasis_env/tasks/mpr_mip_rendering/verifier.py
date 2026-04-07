#!/usr/bin/env python3
"""
Verifier for Generate MIP in MPR Task (`mpr_mip_rendering@1`)

This verifier combines programmatic image analysis with VLM trajectory verification.
Programmatic Analysis:
- In the synthetic CT, the vessel is diagonal. A 1mm thin slice only intersects it 
  at one small point (~900 bright pixels in the exported image).
- A 15mm thick slab Maximum Intensity Projection (MIP) projects a large section of the 
  diagonal tube, resulting in significantly more bright pixels (> 1500).

VLM Trajectory Verification:
- Verifies the agent actually navigated the UI to open MPR and change the setting.
"""

import os
import json
import logging
import tempfile

# Attempt to import framework VLM utils if available
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt to analyze trajectory frames for workflow steps
VLM_PROMPT = """You are evaluating a medical imaging AI agent.
The task was to open a CT scan in Weasis, activate Multiplanar Reconstruction (MPR), change the rendering to Maximum Intensity Projection (MIP), and increase the slab thickness.

Analyze these trajectory screenshots chronologically:
1. Did the agent activate the Multiplanar Reconstruction (MPR) layout? (You should see 3 orthogonal viewing planes: Axial, Coronal, Sagittal).
2. Did the agent interact with the projection settings (dropdowns/sliders showing "MIP" and "Thickness")?
3. In the final states, does the image look like a thick-slab MIP? (Dense structures like vessels appear continuous and long, rather than small cross-sectional dots).

Respond strictly in JSON format:
{
    "mpr_activated": true/false,
    "mip_thickness_interacted": true/false,
    "mip_visually_confirmed": true/false,
    "reasoning": "brief explanation"
}
"""

def verify_mpr_mip_rendering(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_bright_pixels_mip = metadata.get('min_bright_pixels_mip', 1500)
    
    # 1. Retrieve the programmatic results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    export_exists = result.get('export_exists', False)
    created_during_task = result.get('created_during_task', False)
    bright_pixels = result.get('bright_pixels', 0)
    export_size = result.get('export_size_bytes', 0)
    
    # 2. Score File Existence & Anti-Gaming (30 points)
    if export_exists and export_size > 5000:
        score += 15
        feedback_parts.append("Export file found")
        if created_during_task:
            score += 15
            feedback_parts.append("File created during task")
        else:
            feedback_parts.append("File existed before task (possible gaming)")
    elif export_exists:
        score += 5
        feedback_parts.append("Export file found but suspiciously small")
    else:
        feedback_parts.append("Export file NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 3. Score Programmatic MIP Intensity Verification (35 points)
    mip_programmatically_verified = False
    if bright_pixels >= min_bright_pixels_mip:
        score += 35
        mip_programmatically_verified = True
        feedback_parts.append(f"MIP Physics verified ({bright_pixels} bright pixels - thick slab detected)")
    else:
        feedback_parts.append(f"Physics check failed ({bright_pixels} bright pixels - looks like a thin slice)")

    # 4. Score VLM Trajectory Verification (35 points)
    vlm_mpr = False
    vlm_mip = False
    
    if VLM_AVAILABLE and traj:
        try:
            # Sample trajectory to catch MPR UI interactions
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            
            if frames and final:
                images_to_check = frames + [final]
                vlm_result = query_vlm(images=images_to_check, prompt=VLM_PROMPT)
                
                if vlm_result and vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    vlm_mpr = parsed.get("mpr_activated", False)
                    vlm_mip = parsed.get("mip_thickness_interacted", False) or parsed.get("mip_visually_confirmed", False)
                    
                    if vlm_mpr:
                        score += 20
                        feedback_parts.append("VLM: MPR Activated")
                    if vlm_mip:
                        score += 15
                        feedback_parts.append("VLM: MIP/Thickness interacted")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback_parts.append("VLM verification skipped/failed")
    else:
        # Fallback if VLM unavailable: rely heavily on programmatic
        if mip_programmatically_verified:
            score += 35 
            feedback_parts.append("Programmatic passed (VLM skipped)")

    # Determine Pass/Fail
    # Must have the file, and MUST have passed either the programmatic physics check OR both VLM visual checks.
    key_criteria_met = export_exists and created_during_task and (mip_programmatically_verified or (vlm_mpr and vlm_mip))
    passed = (score >= 65) and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }