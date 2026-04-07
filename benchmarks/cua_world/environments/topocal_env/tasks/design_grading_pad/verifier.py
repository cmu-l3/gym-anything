#!/usr/bin/env python3
"""
Verifier for the design_grading_pad task in TopoCal.

VERIFICATION METRICS:
1. Anti-gaming: Ensure output files were generated during the task (not pre-existing).
2. Report file exists and contains properly formatted volumes.
3. Volumetric accuracy: Cut/Fill values extracted must match ground truth within 5%.
4. VLM visual validation: Trajectory frames must show use of the "Explanaciones"
   (Grading) tool, and the final state must feature radial grading slope lines.
"""

import os
import json
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_VERIFICATION_PROMPT = """You are verifying a civil engineering task performed in the CAD software TopoCal (Spanish interface).

Look at these trajectory frames and the final screenshot. Determine the following:
1. Did the agent open the "Explanaciones" (Grading/Platforms) menu or tool window at some point?
2. Does the final workspace show a rectangular building pad with visible radial slope lines (catch lines) extending outwards to the surrounding terrain?
3. Does the final image demonstrate a completed 3D or 2D grading model?

Respond strictly in JSON format:
{
    "used_grading_tool": true/false,
    "shows_slope_lines": true/false,
    "grading_model_completed": true/false,
    "confidence": "low/medium/high",
    "reasoning": "brief explanation"
}
"""

def parse_volume_value(value_str):
    """Safely parse volume string handling potential Spanish commas as decimals."""
    clean_str = value_str.strip().replace(',', '.')
    # If multiple dots exist, keep only the last one (handling thousand separators)
    if clean_str.count('.') > 1:
        parts = clean_str.rsplit('.', 1)
        clean_str = parts[0].replace('.', '') + '.' + parts[1]
    
    try:
        return float(re.search(r'[\d\.]+', clean_str).group(0))
    except (ValueError, AttributeError):
        return None

def verify_design_grading_pad(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    gt_cut = metadata.get('ground_truth_cut_m3', 1250.5)
    gt_fill = metadata.get('ground_truth_fill_m3', 840.2)
    tolerance = metadata.get('volume_tolerance_percent', 5.0)

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/workspace/data/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    start_time = result.get('task_start_time', 0)
    
    # 2. Check Project Save (10 pts)
    if result.get('project_exists'):
        if result.get('project_mtime', 0) >= start_time:
            score += 10
            feedback_parts.append("Project saved successfully")
        else:
            feedback_parts.append("Project file exists but was NOT modified during task (anti-gaming)")
    else:
        feedback_parts.append("Project file not saved")

    # 3. Check Report and Extract Volumes (10 pts + 60 pts accuracy)
    extracted_cut = None
    extracted_fill = None
    
    if result.get('report_exists') and result.get('report_mtime', 0) >= start_time:
        score += 10
        feedback_parts.append("Earthwork report created")
        
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("C:/workspace/data/pad_earthwork.txt", temp_report.name)
            with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read().lower()

            # Spanish/English regex extraction
            cut_match = re.search(r'(?:cut|desmonte)[^\d]*([\d\.,]+)', content, re.IGNORECASE)
            fill_match = re.search(r'(?:fill|terrapl[eé]n)[^\d]*([\d\.,]+)', content, re.IGNORECASE)

            if cut_match:
                extracted_cut = parse_volume_value(cut_match.group(1))
            if fill_match:
                extracted_fill = parse_volume_value(fill_match.group(1))
                
        except Exception as e:
            logger.error(f"Failed to read or parse report: {e}")
            feedback_parts.append("Failed to parse volumes from report")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)
                
        # Cut Accuracy (30 pts)
        if extracted_cut is not None:
            cut_err = abs(extracted_cut - gt_cut) / gt_cut * 100
            if cut_err <= tolerance:
                score += 30
                feedback_parts.append(f"Cut volume accurate ({extracted_cut} m3)")
            else:
                feedback_parts.append(f"Cut volume inaccurate (got {extracted_cut}, err {cut_err:.1f}%)")
        else:
            feedback_parts.append("Cut volume missing")

        # Fill Accuracy (30 pts)
        if extracted_fill is not None:
            fill_err = abs(extracted_fill - gt_fill) / gt_fill * 100
            if fill_err <= tolerance:
                score += 30
                feedback_parts.append(f"Fill volume accurate ({extracted_fill} m3)")
            else:
                feedback_parts.append(f"Fill volume inaccurate (got {extracted_fill}, err {fill_err:.1f}%)")
        else:
            feedback_parts.append("Fill volume missing")
    else:
        feedback_parts.append("Earthwork report missing or invalid timestamp")

    # 4. VLM Verification (20 pts)
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            
            if final:
                vlm_result = query_vlm(
                    prompt=VLM_VERIFICATION_PROMPT,
                    images=frames + [final]
                )
                
                parsed = vlm_result.get("parsed", {})
                vlm_score = 0
                if parsed.get("used_grading_tool", False):
                    vlm_score += 5
                if parsed.get("shows_slope_lines", False):
                    vlm_score += 10
                if parsed.get("grading_model_completed", False):
                    vlm_score += 5
                    
                score += vlm_score
                feedback_parts.append(f"VLM visual check: {vlm_score}/20 pts")
            else:
                feedback_parts.append("VLM skip: No screenshots available")
        except Exception as e:
            logger.error(f"VLM error: {e}")
            feedback_parts.append("VLM verification failed")

    # Pass Criteria: >= 70 pts AND at least one accurate volume extraction
    volume_accurate = (extracted_cut is not None and abs(extracted_cut - gt_cut)/gt_cut*100 <= tolerance) or \
                      (extracted_fill is not None and abs(extracted_fill - gt_fill)/gt_fill*100 <= tolerance)
                      
    passed = (score >= 70) and volume_accurate

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }