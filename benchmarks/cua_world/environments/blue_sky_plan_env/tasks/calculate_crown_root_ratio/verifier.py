#!/usr/bin/env python3
"""
Verifier for calculate_crown_root_ratio task.

Criteria:
1. Files exist (report and screenshot)
2. Files created during task
3. Report content parsing (values within valid range)
4. Ratio calculation correctness
5. VLM Verification of screenshot (Anatomy, Measurements)
"""

import json
import os
import tempfile
import logging
import re
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_calculate_crown_root_ratio(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Define scoring weights
    SCORE_MAX = 100
    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: In Windows env, paths usually map to /tmp/ inside the bridge or are handled by copy_from_env abstraction
        # We assume export_result.ps1 saved to the container's temp which maps to where copy_from_env looks
        copy_from_env("C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence & Timestamp (20 pts)
    report_exists = result.get('report_exists', False)
    screenshot_exists = result.get('screenshot_exists', False)
    report_fresh = result.get('report_created_during_task', False)
    
    if report_exists and report_fresh:
        score += 10
        feedback_parts.append("Report file created")
    elif report_exists:
        score += 5
        feedback_parts.append("Report file exists but timestamp suspicious")
    else:
        feedback_parts.append("Report file missing")

    if screenshot_exists and result.get('screenshot_created_during_task', False):
        score += 10
        feedback_parts.append("Screenshot file created")
    else:
        feedback_parts.append("Screenshot file missing/stale")

    # 3. Parse Report Content (30 pts)
    content = result.get('report_content', '')
    data_valid = False
    
    if report_exists:
        try:
            # Parse values using regex
            # Expected: Crown Height: [Value] mm, Root Length: [Value] mm
            crown_match = re.search(r"Crown Height:\s*([\d\.]+)", content, re.IGNORECASE)
            root_match = re.search(r"Root Length:\s*([\d\.]+)", content, re.IGNORECASE)
            ratio_match = re.search(r"Ratio:\s*([\d\.]+)", content, re.IGNORECASE)

            if crown_match and root_match:
                crown = float(crown_match.group(1))
                root = float(root_match.group(1))
                
                # Check ranges (Metadata defaults: Crown 8-14, Root 10-20)
                min_crown = metadata.get('min_crown_mm', 8.0)
                max_crown = metadata.get('max_crown_mm', 14.0)
                min_root = metadata.get('min_root_mm', 10.0)
                max_root = metadata.get('max_root_mm', 20.0)

                if min_crown <= crown <= max_crown and min_root <= root <= max_root:
                    score += 15
                    feedback_parts.append(f"Measurements in valid range (C:{crown}, R:{root})")
                    data_valid = True
                else:
                    feedback_parts.append(f"Measurements out of physiological range (C:{crown}, R:{root})")

                # Check Ratio Calculation
                calc_ratio = root / crown if crown > 0 else 0
                reported_ratio = float(ratio_match.group(1)) if ratio_match else 0
                
                if abs(calc_ratio - reported_ratio) < 0.1:
                    score += 15
                    feedback_parts.append("Ratio calculated correctly")
                else:
                    feedback_parts.append(f"Ratio calculation mismatch (Calc:{calc_ratio:.2f} vs Rep:{reported_ratio})")
            else:
                feedback_parts.append("Could not parse measurements from report")
        except Exception as e:
            feedback_parts.append(f"Error parsing report: {e}")

    # 4. VLM Verification (50 pts)
    # Get the specific evidence screenshot if available, otherwise use trajectory
    evidence_screenshot_path = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
    evidence_available = False
    
    try:
        if screenshot_exists:
            copy_from_env("C:\\Users\\Docker\\Documents\\tooth_8_ratio.png", evidence_screenshot_path)
            evidence_available = True
    except:
        pass

    vlm_prompt = """
    You are verifying a dental analysis task. 
    The image should show a dental cross-section of an upper central incisor (single root, shovel shape).
    There should be TWO measurement lines visible:
    1. One measuring the Crown (bottom part).
    2. One measuring the Root (top part inside bone).
    
    Check:
    - Is it a dental cross-section view?
    - Is the tooth visible?
    - Are there measurement lines?
    - Does it look like an incisor (Tooth #8)?
    """

    # Use evidence screenshot if available, else final frame
    image_to_check = evidence_screenshot_path if evidence_available else get_final_screenshot(traj)
    
    if image_to_check:
        vlm_res = query_vlm(prompt=vlm_prompt, image=image_to_check)
        
        if vlm_res.get('success'):
            analysis = vlm_res.get('parsed', {})  # Assuming structure, or just use raw text logic
            # Since strict schema isn't enforced in this generic call, let's look for keywords in reasoning if parsed is empty
            reasoning = str(vlm_res)
            
            # Simple keyword checks on VLM output (in a real scenario, use structured output)
            # For this template, we assume the VLM returns a dict with 'criteria_met' bools if prompted with schema,
            # but standard query_vlm returns text. Let's make the prompt request JSON.
            
            json_prompt = vlm_prompt + "\nReturn JSON: {\"is_dental_view\": bool, \"measurements_visible\": bool, \"correct_anatomy\": bool}"
            vlm_json_res = query_vlm(prompt=json_prompt, image=image_to_check)
            
            if vlm_json_res.get('success'):
                parsed = vlm_json_res.get('parsed', {})
                vlm_score = 0
                if parsed.get('is_dental_view'): vlm_score += 10
                if parsed.get('measurements_visible'): vlm_score += 20
                if parsed.get('correct_anatomy'): vlm_score += 20
                
                score += vlm_score
                feedback_parts.append(f"VLM Analysis: {vlm_score}/50 pts")
            else:
                feedback_parts.append("VLM verification failed to parse")
        else:
            feedback_parts.append("VLM query failed")
    else:
        feedback_parts.append("No image available for VLM verification")

    # Cleanup
    if os.path.exists(evidence_screenshot_path):
        os.unlink(evidence_screenshot_path)

    passed = (score >= 70) and data_valid and screenshot_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }