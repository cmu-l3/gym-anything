#!/usr/bin/env python3
"""
Verifier for calculate_cardiothoracic_ratio task.

Multimodal verification:
1. File verification - Check if the report was newly created/modified.
2. Content verification - Parse numeric values via Regex.
3. Math verification - Validate CTR formula (Cardiac / Thoracic) and anatomical constraints (Cardiac < Thoracic).
4. VLM Verification - Check trajectory frames for physical evidence of measurement lines interacting with the image.
"""

import json
import os
import re
import tempfile
import logging

# Attempt to import VLM trajectory tools securely
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cardiothoracic_ratio(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    report_path = metadata.get('export_report_path', '/home/ga/DICOM/exports/ctr_report.txt')
    math_tolerance = metadata.get('math_tolerance', 0.05)

    score = 0
    feedback_parts = []
    
    # --- 1. Validate Base Task Execution ---
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
            
    report_exists = result.get('report_exists', False)
    report_modified = result.get('report_modified_during_task', False)
    image_exists = result.get('image_exists', False)
    
    if report_exists and report_modified:
        score += 15
        feedback_parts.append("Report file created during task")
    elif report_exists:
        feedback_parts.append("Report file exists but is stale (Anti-gaming trigger)")
    else:
        feedback_parts.append("Report file not found")
        
    if image_exists:
        score += 15
        feedback_parts.append("Measurement screenshot exported")
    else:
        feedback_parts.append("Measurement screenshot not exported")

    # --- 2. Extract and Parse Report Data ---
    cardiac_val = None
    thoracic_val = None
    ratio_val = None
    
    if report_exists and report_modified:
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(report_path, temp_report.name)
            with open(temp_report.name, 'r') as f:
                report_content = f.read()
                
            # Regex extracts numeric values (handling formatting variations)
            c_match = re.search(r'Cardiac Diameter:\s*([\d\.]+)', report_content, re.IGNORECASE)
            t_match = re.search(r'Thoracic Diameter:\s*([\d\.]+)', report_content, re.IGNORECASE)
            r_match = re.search(r'Cardiothoracic Ratio:\s*([\d\.]+)', report_content, re.IGNORECASE)
            
            if c_match and t_match and r_match:
                cardiac_val = float(c_match.group(1))
                thoracic_val = float(t_match.group(1))
                ratio_val = float(r_match.group(1))
                score += 20
                feedback_parts.append(f"Values extracted (Cardiac:{cardiac_val}, Thoracic:{thoracic_val}, Ratio:{ratio_val})")
            else:
                feedback_parts.append("Missing one or more required measurement lines in report")
        except Exception as e:
            feedback_parts.append(f"Error parsing report text: {e}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)

    # --- 3. Mathematical & Anatomical Verification ---
    math_correct = False
    if None not in (cardiac_val, thoracic_val, ratio_val):
        if thoracic_val > 0 and cardiac_val > 0:
            if cardiac_val < thoracic_val:
                score += 10
                feedback_parts.append("Physiological constraint met (C < T)")
                
                # Check ratio calculation
                expected_ratio = cardiac_val / thoracic_val
                if abs(expected_ratio - ratio_val) <= math_tolerance:
                    score += 20
                    math_correct = True
                    feedback_parts.append("Calculation mathematically correct")
                else:
                    feedback_parts.append(f"Math Error: expected ~{expected_ratio:.3f}, got {ratio_val}")
            else:
                feedback_parts.append("Invalid constraint: Cardiac diameter is larger than or equal to Thoracic diameter")
        else:
            feedback_parts.append("Error: Diameters must be > 0")

    # --- 4. Trajectory VLM Verification ---
    query_vlm = env_info.get('query_vlm')
    vlm_passed = False
    
    if query_vlm and VLM_AVAILABLE:
        try:
            # Analyze workflow across multiple frames, not just the final one
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """You are analyzing an agent's trajectory in Weasis DICOM viewer. The agent's task is to measure Cardiothoracic Ratio.
Look through these screenshots and determine if:
1. The agent used a Line/Distance measurement tool.
2. There are AT LEAST TWO distinct measurement lines overlaid on the medical image.
Respond exactly in JSON format:
{
    "line_tool_used": true/false,
    "multiple_measurements_visible": true/false,
    "reasoning": "brief explanation"
}"""
            vlm_res = query_vlm(prompt=prompt, images=images)
            
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('line_tool_used') and parsed.get('multiple_measurements_visible'):
                    score += 20
                    vlm_passed = True
                    feedback_parts.append("VLM visual verification: Passed (lines detected)")
                else:
                    feedback_parts.append(f"VLM visual verification failed: {parsed.get('reasoning', 'No lines detected')}")
            else:
                feedback_parts.append("VLM query unsuccessful")
        except Exception as e:
            logger.warning(f"VLM analysis error: {e}")
            feedback_parts.append("VLM verification encountered an error")
    else:
        # Fallback if VLM environment is missing: grant points if the manual image export exists + math is solid
        if image_exists and math_correct:
            score += 20
            vlm_passed = True
            feedback_parts.append("VLM skipped (Full points awarded via fallback logic: Image + Correct Math)")

    # Ensure key milestones are hit to avoid gaming passing threshold
    key_criteria_met = math_correct and report_modified and vlm_passed
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }