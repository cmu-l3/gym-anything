#!/usr/bin/env python3
"""
Verifier for measure_orthopedic_cobb_angle task.

Verification Strategy:
1. File Checks (25 pts): 
   - PNG export exists, is reasonably sized, created after task start.
   - TXT documentation exists, created after task start, contains 'cobb'.
2. VLM Trajectory Check (75 pts):
   - Confirms measurement tool is visible on screen.
   - Distinguishes 4-point Cobb Angle from standard 3-point Angle.
"""

import json
import os
import tempfile
import logging

try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    print("Warning: gym_anything.vlm not available. VLM verification will be bypassed or scored 0.")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are an expert radiology application tester verifying a user's action in Weasis DICOM Viewer.

Look at these screenshots. The agent was asked to use the specialized 'Cobb Angle' measurement tool.
A Cobb Angle measurement has a very distinct visual signature compared to a standard geometric angle:
1. Cobb Angle: The user draws TWO completely separate, non-contiguous line segments. The software then automatically draws perpendicular lines extending from these segments until they intersect, showing the angle value in degrees.
2. Standard Angle (FAIL condition): The user draws two connected lines that meet at a single vertex (creating a 'V' shape). 

Analyze the images to determine if a true Cobb Angle measurement was performed. Look at all provided frames.

Respond ONLY in valid JSON format:
{
    "measurement_overlay_present": true/false,
    "is_cobb_angle_tool": true/false,
    "is_standard_v_angle": true/false,
    "reasoning": "brief explanation"
}
"""

def verify_measure_orthopedic_cobb_angle(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Read exported results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # File criterion A: Exported screenshot
    if result.get('image_exists') and result.get('image_created_during_task'):
        if result.get('image_size_bytes', 0) > 10240: # > 10KB
            score += 15
            feedback_parts.append("Screenshot exported properly")
        else:
            feedback_parts.append("Screenshot exported but size is abnormally small")
    else:
        feedback_parts.append("Screenshot not found or created before task started (gaming attempt)")

    # File criterion B: Text documentation
    if result.get('text_exists') and result.get('text_created_during_task'):
        text_content = result.get('text_content', '').lower()
        if 'cobb' in text_content:
            score += 10
            feedback_parts.append("Correct tool documented in text file")
        else:
            feedback_parts.append(f"Text file exists but missing keyword 'cobb'. Content: {text_content[:20]}...")
    else:
        feedback_parts.append("Measurement text documentation missing or invalid timestamp")

    # 2. VLM Trajectory Verification
    if VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            
            # Combine frames, avoiding duplicates if trajectory is very short
            images_to_analyze = frames
            if final_frame and final_frame not in images_to_analyze:
                images_to_analyze.append(final_frame)
                
            vlm_response = query_vlm(images=images_to_analyze, prompt=VLM_PROMPT)
            
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                
                # Check 1: Any measurement present
                if parsed.get("measurement_overlay_present", False):
                    score += 25
                    feedback_parts.append("VLM confirmed measurement overlay visible")
                else:
                    feedback_parts.append("VLM could not find any measurement overlay")
                    
                # Check 2: Correct tool (Cobb Angle, not standard angle)
                if parsed.get("is_cobb_angle_tool", False):
                    score += 50
                    feedback_parts.append("VLM verified 4-point Cobb Angle tool was used")
                elif parsed.get("is_standard_v_angle", False):
                    feedback_parts.append("VLM detected a standard 3-point angle. FAILED: Cobb Angle tool is required.")
                else:
                    feedback_parts.append("VLM could not identify the specific Cobb Angle characteristics.")
                    
            else:
                feedback_parts.append(f"VLM verification query failed: {vlm_response.get('error', 'Unknown')}")
                
        except Exception as e:
            logger.error(f"Error during VLM verification: {e}")
            feedback_parts.append("Error executing VLM trajectory check.")
    else:
        feedback_parts.append("VLM module unavailable, cannot visually verify measurement.")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }