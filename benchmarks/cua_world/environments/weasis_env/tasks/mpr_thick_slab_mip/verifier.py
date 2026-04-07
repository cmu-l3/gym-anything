#!/usr/bin/env python3
"""
Verifier for MPR Thick Slab MIP task.

Evaluates:
1. Output file existence and validity (Screenshot and TXT).
2. Anti-gaming (files must be created during the task, not pre-existing).
3. VLM Analysis of Trajectory: MPR Layout active.
4. VLM Analysis of Trajectory/Screenshot: MIP Projection selected.
5. VLM Analysis of Trajectory/Screenshot: Thickness set to 15 or greater.
"""

import os
import json
import logging
import tempfile
import sys

# Import VLM utilities from the gym_anything framework
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    pass # Handled gracefully if not directly available; we inject it dynamically in the runner

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are an expert radiology software application reviewer.
You are evaluating an AI agent's performance in Weasis DICOM Viewer.
The agent was asked to open a Multiplanar Reconstruction (MPR) viewer, select Maximum Intensity Projection (MIP), and set the slab thickness to at least 15mm.

Look at the provided sequence of screenshots from the agent's workflow. Determine the following:

1. mpr_active: Did the agent successfully activate the MPR layout? 
   (Look for the viewer split into multiple orthogonal planes, usually 3 views: axial, coronal, sagittal).
2. mip_selected: In the MPR toolbar (typically above the MPR views), is the Projection mode set to "MIP" or "Maximum"? 
   (The default is usually 'None', 'Average', or 'Min').
3. thickness_set: In the MPR toolbar, is the thickness value set to 15 (or greater)? 
   (Look for a numeric input box or slider labeled 'Thickness' or similar next to the projection dropdown).

Output a strict JSON object with these boolean keys:
{
  "mpr_active": true/false,
  "mip_selected": true/false,
  "thickness_set": true/false,
  "reasoning": "Briefly explain the evidence found in the screenshots."
}
"""

def verify_mpr_thick_slab(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification framework error: copy_from_env unavailable."}
        
    # 1. Fetch JSON result programmatic data
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read programmatic result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Check outputs programmatic (20 points total)
    png_exists = result.get("png_exists", False)
    png_valid = result.get("png_created_during_task", False) and result.get("png_size_bytes", 0) > 1024
    
    txt_exists = result.get("txt_exists", False)
    txt_valid = result.get("txt_created_during_task", False)
    txt_content = result.get("txt_content", "").lower()
    
    if png_exists and png_valid:
        score += 10
        feedback_parts.append("Screenshot saved")
    else:
        feedback_parts.append("Screenshot missing/invalid")
        
    if txt_exists and txt_valid:
        score += 10
        feedback_parts.append("Settings TXT saved")
        if "mip" in txt_content or "15" in txt_content:
            feedback_parts.append("TXT content looks relevant")
    else:
        feedback_parts.append("Settings TXT missing/invalid")
        
    # 2. VLM Trajectory Verification (80 points total)
    vlm_success = False
    if query_vlm:
        try:
            # We must use the framework's functions or fallback manually reading images if not present
            if hasattr(env_info, 'get_final_screenshot'):
                 # For robust testing, try to sample multiple frames + the target image from container if needed
                 pass
            
            # Using standard vlm trajectory sample
            images = []
            if 'sample_trajectory_frames' in globals():
                images = sample_trajectory_frames(traj, n=4)
                images.append(get_final_screenshot(traj))
            else:
                # Fallback to getting final state from trajectory directly if helpers aren't injected
                if traj and len(traj) > 0 and 'image' in traj[-1]:
                    images = [traj[max(0, len(traj)-3)]['image'], traj[-1]['image']]
                    
            vlm_response = query_vlm(images=images, prompt=VLM_PROMPT)
            
            if vlm_response and vlm_response.get("success"):
                vlm_parsed = vlm_response.get("parsed", {})
                
                mpr_active = vlm_parsed.get("mpr_active", False)
                mip_selected = vlm_parsed.get("mip_selected", False)
                thickness_set = vlm_parsed.get("thickness_set", False)
                
                if mpr_active:
                    score += 30
                    feedback_parts.append("VLM: MPR layout detected")
                else:
                    feedback_parts.append("VLM: MPR layout not active")
                    
                if mip_selected:
                    score += 25
                    feedback_parts.append("VLM: MIP selected")
                else:
                    feedback_parts.append("VLM: MIP not selected")
                    
                if thickness_set:
                    score += 25
                    feedback_parts.append("VLM: Thickness 15+ set")
                else:
                    feedback_parts.append("VLM: Thickness not set properly")
                    
                vlm_success = True
            else:
                feedback_parts.append("VLM query failed or unparseable")
        except Exception as e:
            feedback_parts.append(f"VLM Exception: {str(e)}")
            
    if not vlm_success:
        # If VLM is totally unavailable, fallback to giving some points if text file clearly states the right settings
        if "mip" in txt_content and "15" in txt_content and png_valid:
            score += 40
            feedback_parts.append("VLM unavailable, partial credit awarded based on TXT content")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }