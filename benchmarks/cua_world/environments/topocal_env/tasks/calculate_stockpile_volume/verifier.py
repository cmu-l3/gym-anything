#!/usr/bin/env python3
"""
Verifier for the TopoCal Stockpile Volume task.

Verification Strategy:
1. Programmatic: 
   - Check if `inventory_report.txt` was created/modified during the task.
   - Parse the numeric value from the text file.
   - Verify it falls within ±5% of the ground truth mathematically generated volume (37,699.1 m³).
2. VLM Trajectory:
   - Check trajectory frames to ensure the user actually loaded the data in TopoCal,
     generated the TIN, and used the volume dialog (preventing python/script bypass).
"""

import os
import json
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM prompt to verify actual workflow within TopoCal
VLM_PROMPT = """You are evaluating an AI agent performing a volumetric surveying task in a CAD application (TopoCal).
Please look at these trajectory screenshots and determine if the agent actually used the software to perform the work.

We are looking for evidence of the following:
1. Did the agent import point cloud data into the application? (Visible points in the drawing area)
2. Did the agent generate a Triangulated Irregular Network (TIN/MDT)? (Visible mesh/triangles connecting points)
3. Is there evidence of the agent interacting with a Volume calculation dialog or tool?
4. Is this the TopoCal application interface?

Respond ONLY with a valid JSON object matching this schema:
{
    "imported_points_visible": boolean,
    "tin_mesh_visible": boolean,
    "volume_dialog_interaction": boolean,
    "is_topocal_interface": boolean,
    "confidence": "high|medium|low",
    "reasoning": "Brief explanation"
}
"""

def extract_volume_from_text(text: str) -> float:
    """Extracts the best candidate for a volume measurement from raw text."""
    if not text:
        return None
        
    # Remove thousand separators for easier parsing
    text_clean = text.replace(',', '')
    
    # Find all decimal numbers
    matches = re.findall(r'-?\d+\.\d+|-?\d+', text_clean)
    
    if not matches:
        return None
        
    # Convert matches to floats
    numbers = [float(m) for m in matches]
    
    # If there are multiple numbers, find the one closest to our expected range 
    # (heuristically, the volume is usually the largest number or the one explicitly labeled)
    # A simple approach is returning the largest number found if multiple exist, 
    # assuming coordinates or elevations are smaller than 37k
    return max(numbers)

def verify_calculate_stockpile_volume(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth_volume', 37699.1)
    tolerance_pct = metadata.get('tolerance_percent', 5.0)
    
    # Calculate acceptable range
    min_acceptable = ground_truth * (1 - (tolerance_pct / 100))
    max_acceptable = ground_truth * (1 + (tolerance_pct / 100))
    
    feedback_parts = []
    score = 0
    max_score = 100
    
    # 1. Retrieve the exported JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        # Use Windows-style path mapped to container
        copy_from_env("C:/temp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r', encoding='utf-8') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result data: {e}")
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # 2. Programmatic Verification
    report_exists = result_data.get('report_exists', False)
    report_created_during = result_data.get('report_created_during_task', False)
    report_content = result_data.get('report_content', '')
    
    if not report_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Inventory report file was not found. Task incomplete."
        }
        
    if not report_created_during:
        feedback_parts.append("Warning: Report file timestamp precedes task start (potential gaming).")
    else:
        score += 15
        feedback_parts.append("Report created during task.")
        
    reported_volume = extract_volume_from_text(report_content)
    
    volume_accurate = False
    if reported_volume is None:
        feedback_parts.append("Could not extract a numeric volume value from the report.")
    else:
        feedback_parts.append(f"Extracted volume: {reported_volume:.1f} m³.")
        if min_acceptable <= reported_volume <= max_acceptable:
            score += 45
            volume_accurate = True
            feedback_parts.append(f"Volume is within {tolerance_pct}% tolerance of ground truth ({ground_truth:.1f} m³).")
        else:
            feedback_parts.append(f"Volume is inaccurate. Expected ~{ground_truth:.1f} m³ (±{tolerance_pct}%).")

    # 3. VLM Trajectory Verification
    vlm_passed = False
    if query_vlm:
        try:
            # We must import from gym_anything here inside the verifier context
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample frames to prove the workflow was done in TopoCal
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            if final_frame:
                frames.append(final_frame)
                
            if frames:
                vlm_result = query_vlm(prompt=VLM_PROMPT, images=frames)
                
                if vlm_result.get('success') and 'parsed' in vlm_result:
                    parsed = vlm_result['parsed']
                    is_topocal = parsed.get('is_topocal_interface', False)
                    tin_visible = parsed.get('tin_mesh_visible', False)
                    dialog_used = parsed.get('volume_dialog_interaction', False)
                    
                    if is_topocal:
                        score += 10
                    if tin_visible:
                        score += 15
                        feedback_parts.append("VLM confirmed TIN mesh generation.")
                    if dialog_used:
                        score += 15
                        feedback_parts.append("VLM confirmed Volume dialog interaction.")
                        
                    if is_topocal and (tin_visible or dialog_used):
                        vlm_passed = True
                else:
                    feedback_parts.append("VLM validation failed to parse.")
            else:
                feedback_parts.append("No trajectory frames available for VLM.")
        except Exception as e:
            logger.error(f"VLM Exception: {e}")
            feedback_parts.append(f"VLM validation error.")
            
    # Calculate Final Pass/Fail
    # To pass: MUST have generated the report, MUST have accurate volume, MUST show VLM evidence
    passed = (score >= 70) and volume_accurate and vlm_passed
    
    return {
        "passed": passed,
        "score": min(score, max_score),
        "feedback": " | ".join(feedback_parts)
    }