#!/usr/bin/env python3
"""Verifier for RECIST Tumor Measurement task"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_recist_measurement(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Read result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Report existence and freshness
    report_exists = result.get('report_exists', False)
    report_created = result.get('report_created', False)
    
    if report_exists and report_created:
        score += 10
        feedback_parts.append("Report file created")
    elif report_exists:
        feedback_parts.append("Report file exists but was not created during task")
    else:
        feedback_parts.append("Report file missing")
        
    # 2. Extract values from report content directly utilizing copy_from_env
    valid_values = False
    if report_exists:
        report_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/home/ga/DICOM/exports/recist_report.txt", report_temp.name)
            with open(report_temp.name, 'r') as f:
                report_content = f.read()
                
            long_axis_match = re.search(r'Long Axis:\s*([\d\.]+)', report_content, re.IGNORECASE)
            short_axis_match = re.search(r'Short Axis:\s*([\d\.]+)', report_content, re.IGNORECASE)
            
            if long_axis_match and short_axis_match:
                long_val = float(long_axis_match.group(1))
                short_val = float(short_axis_match.group(1))
                if long_val > 0 and short_val > 0:
                    score += 20
                    feedback_parts.append(f"Values extracted (Long: {long_val}, Short: {short_val})")
                    valid_values = True
                else:
                    feedback_parts.append("Extracted values are not positive")
            else:
                feedback_parts.append("Could not parse Long/Short axis values from report")
        except Exception as e:
            feedback_parts.append(f"Failed to read report file contents: {e}")
        finally:
            if os.path.exists(report_temp.name):
                os.unlink(report_temp.name)
    else:
        feedback_parts.append("Cannot parse missing report")
        
    # 3. Screenshot existence
    screenshot_exists = result.get('screenshot_exists', False)
    screenshot_created = result.get('screenshot_created', False)
    
    if screenshot_exists and screenshot_created:
        score += 10
        feedback_parts.append("Screenshot saved")
    elif screenshot_exists:
        feedback_parts.append("Screenshot exists but not created during task")
    else:
        feedback_parts.append("Screenshot missing")
        
    # 4. VLM Verification
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        prompt = """You are evaluating a medical agent performing a RECIST 1.1 tumor measurement in Weasis DICOM Viewer.
The agent must draw two intersecting, roughly perpendicular measurement lines (a cross/plus shape) across an anatomical structure in the image.

Analyze the sequence of screenshots. Look for distance measurement annotations (lines with length values).
Assess:
1. "lines_visible": Are there two (or a distinct orthogonal pair of) distance measurement lines visible on the image?
2. "lines_intersect": Do the two lines physically intersect each other?
3. "lines_perpendicular": Is the intersection angle roughly perpendicular (approx 90 degrees)?
4. "placed_on_structure": Are the lines placed over a cohesive visual structure (like a tumor, organ, or bright spot) rather than empty black space?

Respond strictly in JSON format:
{
    "lines_visible": true/false,
    "lines_intersect": true/false,
    "lines_perpendicular": true/false,
    "placed_on_structure": true/false,
    "confidence": "high/medium/low"
}
"""
        vlm_resp = query_vlm(images=images, prompt=prompt)
        
        if vlm_resp and vlm_resp.get("success"):
            parsed = vlm_resp.get("parsed", {})
            if parsed.get("lines_visible"):
                score += 15
                feedback_parts.append("VLM: Lines visible")
            
            if parsed.get("lines_intersect"):
                score += 15
                feedback_parts.append("VLM: Lines intersect")
                
            if parsed.get("lines_perpendicular"):
                score += 15
                feedback_parts.append("VLM: Lines perpendicular")
                
            if parsed.get("placed_on_structure"):
                score += 15
                feedback_parts.append("VLM: On structure")
        else:
            feedback_parts.append("VLM verification failed to execute")
            
    except Exception as e:
        logger.warning(f"VLM error: {e}")
        feedback_parts.append(f"VLM check bypassed ({e})")

    # Pass condition
    passed = (score >= 70) and valid_values
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }