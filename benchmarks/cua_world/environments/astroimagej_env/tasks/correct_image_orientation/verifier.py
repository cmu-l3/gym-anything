#!/usr/bin/env python3
"""
Verifier for Determine and Apply Image Orientation Correction task.

Verification Strategy:
1. Programmatic Checks (50 points):
   - Report exists and contains WCS keywords (10 points)
   - Parsed Position Angle (PA) from report matches ground truth (15 points)
   - Parsed applied rotation from report matches required rotation (15 points)
   - Output FITS exists and image data was modified from original (10 points)
   
2. VLM Trajectory Verification (50 points):
   - Agent opened the FITS header / info window (15 points)
   - Agent opened the Rotation dialog (15 points)
   - Final screenshot shows the image visibly rotated compared to start (20 points)
   
Pass threshold: 60 points + required key actions.
"""

import os
import json
import re
import tempfile
import logging
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt for verifying the progression of the task
VLM_PROMPT = """You are evaluating an AI agent performing an image rotation task in AstroImageJ.
I am providing a sequence of screenshots sampled from the agent's interaction (chronological order).

The agent's goal was to:
1. Open a FITS image.
2. Inspect the FITS Header or Info window to find WCS keywords (CD1_1, etc.).
3. Use the "Rotate" tool (Image > Transform > Rotate).
4. Save the rotated image and a text report.

Please analyze the screenshots and determine:
1. header_inspected: Is there a window open showing the FITS header, image info, or text containing "CD1_1", "CD1_2"?
2. rotation_dialog_used: Is there a dialog box visible for "Rotate" (asking for an angle)?
3. image_visibly_rotated: Comparing the first frame where the image is loaded to the final frame, does the main image appear rotated? (Look at the orientation of the bright star clusters or the overall shape of the image borders, which might have black triangular padding after rotation).

Respond EXACTLY in this JSON format:
{
    "header_inspected": true/false,
    "rotation_dialog_used": true/false,
    "image_visibly_rotated": true/false,
    "reasoning": "Brief explanation of what you observed in the frames"
}
"""

def verify_correct_image_orientation(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    angle_tolerance = metadata.get('angle_tolerance_deg', 5.0)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Load exported result and ground truth
    # ---------------------------------------------------------
    result = {}
    try:
        temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)
            
    gt = {}
    try:
        temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/orientation_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read ground truth: {e}")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
            
    # Ground truth values
    gt_pa = gt.get('position_angle_deg', 0.0)
    
    # ---------------------------------------------------------
    # 2. Programmatic Verification
    # ---------------------------------------------------------
    
    # Check FITS Output
    fits_exists = result.get('output_fits_exists', False)
    fits_modified = result.get('output_fits_modified_from_original', False)
    
    if fits_exists and fits_modified:
        score += 10
        feedback_parts.append("✅ Output FITS saved and correctly modified/rotated")
    elif fits_exists:
        score += 3
        feedback_parts.append("⚠️ Output FITS saved but appears identical to original (not rotated)")
    else:
        feedback_parts.append("❌ Output FITS not found")

    # Check Report
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    
    parsed_pa = None
    parsed_rot = None
    
    if report_exists:
        score += 5
        feedback_parts.append("✅ Report file created")
        
        # Check for keywords
        if 'cd1_1' in report_content.lower() or 'cd1_2' in report_content.lower():
            score += 5
            feedback_parts.append("✅ WCS keywords documented in report")
        else:
            feedback_parts.append("⚠️ WCS keywords not found in report")
            
        # Parse Position Angle
        pa_match = re.search(r'(?:PA|Position Angle|angle of North).*?([-+]?\d*\.\d+|\d+)', report_content, re.IGNORECASE)
        if pa_match:
            parsed_pa = float(pa_match.group(1))
            
            # Since conventions differ, accept PA, -PA, or 360-PA
            pa_diff = min(abs(parsed_pa - gt_pa), abs(parsed_pa + gt_pa), abs(parsed_pa - (gt_pa % 360)))
            if pa_diff <= angle_tolerance:
                score += 15
                feedback_parts.append(f"✅ Correct Position Angle reported ({parsed_pa} deg)")
            else:
                feedback_parts.append(f"❌ Reported Position Angle ({parsed_pa}) differs from true PA ({gt_pa:.1f})")
        else:
            feedback_parts.append("❌ Could not parse Position Angle from report")
            
        # Parse Applied Rotation
        rot_match = re.search(r'(?:Rotation|Applied Rotation|Rotated by).*?([-+]?\d*\.\d+|\d+)', report_content, re.IGNORECASE)
        if rot_match:
            parsed_rot = float(rot_match.group(1))
            # AIJ rotates counter-clockwise. To orient North up, we usually rotate by -PA.
            expected_rot = -gt_pa
            rot_diff = min(abs(parsed_rot - expected_rot), abs(parsed_rot + expected_rot), abs(parsed_rot - (expected_rot % 360)))
            
            if rot_diff <= angle_tolerance:
                score += 15
                feedback_parts.append(f"✅ Correct Applied Rotation reported ({parsed_rot} deg)")
            else:
                feedback_parts.append(f"⚠️ Reported Applied Rotation ({parsed_rot}) may be incorrect (expected ~{expected_rot:.1f})")
        else:
            feedback_parts.append("❌ Could not parse Applied Rotation from report")
            
    else:
        feedback_parts.append("❌ Report file not found")

    # ---------------------------------------------------------
    # 3. VLM Trajectory Verification
    # ---------------------------------------------------------
    vlm_passed = False
    
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        if frames:
            try:
                vlm_response = query_vlm(
                    prompt=VLM_PROMPT,
                    images=frames
                )
                
                if vlm_response.get('success'):
                    parsed = vlm_response.get('parsed', {})
                    
                    if parsed.get('header_inspected', False):
                        score += 15
                        feedback_parts.append("✅ VLM confirmed FITS header inspection")
                        
                    if parsed.get('rotation_dialog_used', False):
                        score += 15
                        feedback_parts.append("✅ VLM confirmed rotation dialog used")
                        
                    if parsed.get('image_visibly_rotated', False):
                        score += 20
                        feedback_parts.append("✅ VLM confirmed final image is visibly rotated")
                        vlm_passed = True
                    else:
                        feedback_parts.append("❌ VLM did not observe the final image being rotated")
                else:
                    feedback_parts.append(f"⚠️ VLM query failed: {vlm_response.get('error')}")
            except Exception as e:
                feedback_parts.append(f"⚠️ VLM verification error: {str(e)}")
        else:
            feedback_parts.append("⚠️ No trajectory frames available for VLM verification")
    else:
        feedback_parts.append("⚠️ VLM capability not available")

    # ---------------------------------------------------------
    # Final Score Calculation
    # ---------------------------------------------------------
    
    # Key criteria: FITS saved, Report saved, and at least one proof of rotation (VLM or programmatic FITS change)
    key_criteria_met = fits_exists and report_exists and (fits_modified or vlm_passed)
    
    passed = (score >= 60) and key_criteria_met

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": "\n".join(feedback_parts),
        "details": {
            "gt_pa": gt_pa,
            "parsed_pa": parsed_pa,
            "parsed_rot": parsed_rot,
            "fits_modified": fits_modified
        }
    }