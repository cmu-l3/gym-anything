#!/usr/bin/env python3
"""
Verifier for Measure Signal-to-Background Ratio task.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_measure_signal_to_background_ratio(traj, env_info, task_info):
    """
    Verify the math, ranges, file creation, and VLM evidence for the QA measurement task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Initialize VLM modules
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        has_vlm = True
    except ImportError:
        has_vlm = False
        logger.warning("VLM module not found, visual verification will be skipped.")

    metadata = task_info.get('metadata', {})
    bone_min = metadata.get('bone_mean_min', 100)
    bone_max = metadata.get('bone_mean_max', 3000)
    air_min = metadata.get('air_mean_min', -1100)
    air_max = metadata.get('air_mean_max', -700)
    tolerance = metadata.get('tolerance', 0.05)

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
    
    text_exists = result.get('text_exists', False)
    img_exists = result.get('img_exists', False)
    created_during_task = result.get('created_during_task', False)
    text_content = result.get('text_content', '')
    
    # CRITERION 1: File Creation (10 pts)
    if text_exists and img_exists:
        if created_during_task:
            score += 10
            feedback_parts.append("Files created successfully (+10)")
        else:
            feedback_parts.append("Files exist but timestamps indicate they were not created during this task session")
    else:
        feedback_parts.append("Missing expected output text file or screenshot")
        
    # Regex parsing
    bone_mean = None
    air_mean = None
    ratio = None
    
    b_match = re.search(r'Bone Mean:\s*([+-]?\d*\.?\d+)', text_content, re.IGNORECASE)
    a_match = re.search(r'Air Mean:\s*([+-]?\d*\.?\d+)', text_content, re.IGNORECASE)
    r_match = re.search(r'Ratio:\s*([+-]?\d*\.?\d+)', text_content, re.IGNORECASE)
    
    if b_match: bone_mean = float(b_match.group(1))
    if a_match: air_mean = float(a_match.group(1))
    if r_match: ratio = float(r_match.group(1))
    
    # CRITERION 2: Bone Accuracy Check (20 pts)
    bone_valid = False
    if bone_mean is not None:
        if bone_min <= bone_mean <= bone_max:
            score += 20
            bone_valid = True
            feedback_parts.append(f"Bone mean physically valid: {bone_mean} HU (+20)")
        else:
            feedback_parts.append(f"Bone mean {bone_mean} HU out of logical bounds [{bone_min}, {bone_max}]")
    else:
        feedback_parts.append("Bone Mean not found in text file")

    # CRITERION 3: Air Accuracy Check (20 pts)
    air_valid = False
    if air_mean is not None:
        if air_min <= air_mean <= air_max:
            score += 20
            air_valid = True
            feedback_parts.append(f"Air mean physically valid: {air_mean} HU (+20)")
        else:
            feedback_parts.append(f"Air mean {air_mean} HU out of logical bounds [{air_min}, {air_max}]")
    else:
        feedback_parts.append("Air Mean not found in text file")

    # CRITERION 4: Math Check (25 pts)
    math_valid = False
    if bone_valid and air_valid and ratio is not None:
        expected_ratio = bone_mean / air_mean if air_mean != 0 else 0
        if abs(expected_ratio - ratio) <= tolerance:
            score += 25
            math_valid = True
            feedback_parts.append(f"Ratio calculation correct: {ratio} (+25)")
        else:
            feedback_parts.append(f"Ratio calculation incorrect (Expected {expected_ratio:.3f}, Agent reported {ratio})")
    elif ratio is None:
        feedback_parts.append("Ratio not found in text file")

    # CRITERION 5: VLM Visual Verification (25 pts)
    vlm_passed = False
    if has_vlm:
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        prompt = """You are analyzing a medical imaging task where an agent must draw two ROIs (Regions of Interest) on a CT scan using Weasis.
Look at this sequence of screenshots from the agent's trajectory.
Please evaluate the following carefully:
1. Is a medical CT scan visible in the viewer?
2. Are there at least two separate ROI shapes (like ellipses or polygons) drawn on the image?
3. Is one ROI placed on a bright anatomical structure (bone or dense tissue) and another ROI placed in the black background space outside the patient body (air)?

Reply in strict JSON format mapping to boolean keys, and include a reasoning field to explain your analysis:
{
    "reasoning": "your step-by-step analysis",
    "ct_scan_visible": true/false,
    "rois_drawn": true/false,
    "bone_and_air_measured": true/false
}
"""
        try:
            vlm_response = query_vlm(prompt=prompt, images=images)
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if isinstance(parsed, dict) and parsed.get("ct_scan_visible") and parsed.get("rois_drawn") and parsed.get("bone_and_air_measured"):
                    score += 25
                    vlm_passed = True
                    feedback_parts.append("VLM visual verification passed (+25)")
                else:
                    feedback_parts.append(f"VLM verification failed to meet criteria. Reasoning: {parsed.get('reasoning', 'none')}")
            else:
                feedback_parts.append(f"VLM query failed: {vlm_response.get('error')}")
        except Exception as e:
            feedback_parts.append(f"VLM exception: {e}")
    else:
        feedback_parts.append("VLM library not available, skipping visual check")
        # Ensure it's still possible to pass if VLM is unavailable but everything else was flawless
        if math_valid and bone_valid and air_valid:
            score += 25

    # Determine Pass / Fail
    passed = (score >= 80)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }