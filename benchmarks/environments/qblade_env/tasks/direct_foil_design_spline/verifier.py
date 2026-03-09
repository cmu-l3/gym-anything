#!/usr/bin/env python3
"""
Verifier for direct_foil_design_spline task.
Verifies QBlade project creation, correct naming, and visual workflow.
"""

import json
import tempfile
import os
import logging
import sys

# Add parent directory to path to import vlm_utils if needed, 
# though we usually assume gym_anything.vlm availability in the environment
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback for local testing
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}
    def sample_trajectory_frames(traj, n): return []
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_direct_foil_design_spline(traj, env_info, task_info):
    """
    Verify the custom airfoil design task.
    
    Scoring (100 pts total):
    - [15] Project file exists
    - [10] Project file created/modified during task
    - [10] File has valid content size (>500B)
    - [15] Airfoil named 'SymCustom15' found in file
    - [10] Foil geometry data detected in file
    - [20] VLM: Trajectory shows Direct Foil Design module usage
    - [10] VLM: Airfoil appears symmetric
    - [10] VLM: Airfoil appears approx 15% thick
    """
    
    # 1. Setup and retrieve programmatic results
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # Read result JSON from container
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

    # 2. Programmatic Verification (60 pts)
    
    # Check File Existence (15 pts)
    if result.get("file_exists"):
        score += 15
        feedback_parts.append("Project file saved.")
    else:
        feedback_parts.append("Project file NOT found.")
    
    # Check Timestamp (10 pts)
    if result.get("file_created_during_task"):
        score += 10
    elif result.get("file_exists"):
        feedback_parts.append("File exists but was not modified during task.")

    # Check File Size (10 pts)
    if result.get("file_size", 0) > 500:
        score += 10
    elif result.get("file_exists"):
        feedback_parts.append(f"File too small ({result.get('file_size')} bytes).")

    # Check Airfoil Name (15 pts)
    if result.get("name_found_in_file"):
        score += 15
        feedback_parts.append("Airfoil 'SymCustom15' found in project.")
    else:
        feedback_parts.append("Airfoil name 'SymCustom15' NOT found in file.")

    # Check Data Content (10 pts)
    if result.get("has_data_content"):
        score += 10
    else:
        feedback_parts.append("No foil geometry data detected in file.")

    # 3. VLM Verification (40 pts)
    # We verify the workflow and the visual shape of the airfoil
    
    frames = sample_trajectory_frames(traj, n=6)
    final_shot = get_final_screenshot(traj)
    
    if frames and final_shot:
        vlm_prompt = """
        Analyze these screenshots of a user working in QBlade.
        
        The user is supposed to:
        1. Go to the "Direct Foil Design" or "Airfoil Design" module (look for graphs, curves, or splines).
        2. Create a SYMMETRIC airfoil (upper and lower curves are mirror images).
        3. Make it approximately 15% thick (moderately thick, not thin like a flat plate, not a circle).
        
        Answer the following in JSON:
        {
            "module_visible": boolean, // Is a foil design/graph view visible?
            "spline_controls_visible": boolean, // Are there control points/circles/tangent handles visible?
            "is_symmetric": boolean, // Does the final shape look symmetric about the center line?
            "thickness_ok": boolean, // Does it look like a realistic airfoil (approx 10-20% thickness)?
            "confidence": "low"|"medium"|"high"
        }
        """
        
        vlm_res = query_vlm(prompt=vlm_prompt, images=frames + [final_shot])
        
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            
            # Module Usage (20 pts)
            if parsed.get("module_visible") or parsed.get("spline_controls_visible"):
                score += 20
                feedback_parts.append("VLM: Design module usage verified.")
            else:
                feedback_parts.append("VLM: Could not verify design module usage.")
                
            # Symmetry (10 pts)
            if parsed.get("is_symmetric"):
                score += 10
                feedback_parts.append("VLM: Airfoil symmetry verified.")
            else:
                feedback_parts.append("VLM: Airfoil does not appear symmetric.")
                
            # Thickness (10 pts)
            if parsed.get("thickness_ok"):
                score += 10
                feedback_parts.append("VLM: Airfoil thickness looks correct.")
            else:
                feedback_parts.append("VLM: Airfoil thickness appears incorrect.")
        else:
            feedback_parts.append("VLM verification failed.")
    else:
        feedback_parts.append("No screenshots available for VLM.")

    # 4. Final Result
    passed = score >= 60 and result.get("file_exists") and result.get("name_found_in_file")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }