#!/usr/bin/env python3
"""
Verifier for Calculate Photometric Zero Point task.

Scoring (100 points total):
  1. Measurement file exists and created during task (15 pts)
  2. Report file exists and created during task (10 pts)
  3. Calculated ZP Accuracy vs Ground Truth (40 pts)
     - Full 40 pts if within +/- 0.1
     - Partial 20 pts if within +/- 0.3
  4. VLM verification of trajectory (35 pts)
     - Confirms agent actually used AstroImageJ to perform photometry
"""

import json
import os
import tempfile
import logging
import re

from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are analyzing a sequence of screenshots from an agent performing aperture photometry in AstroImageJ to calculate a photometric zero point.
The images are sampled chronologically from the agent's full interaction.

Look for evidence of the following workflow:
1. Configuring aperture settings (Radius=15, Inner=20, Outer=30). You might see an "Aperture Settings" dialog window.
2. Placing apertures on stars (circular overlays on the grayscale astronomical image).
3. A Measurements/Results table appearing with flux/Source-Sky values.

Based on the trajectory frames, did the agent actively perform aperture photometry in AstroImageJ?

Respond in JSON format:
{
    "aperture_settings_dialog_seen": true/false,
    "apertures_placed_on_stars": true/false,
    "measurements_table_seen": true/false,
    "photometry_actively_performed": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "Brief explanation of what visual evidence supports your conclusion"
}
"""

def verify_zero_point(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []
    
    # 1. Read results JSON
    result = {}
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)

    # 2. Read Ground Truth
    gt_zp = None
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/zp_ground_truth.txt", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_zp = float(f.read().strip())
    except Exception as e:
        feedback_parts.append(f"Could not load Ground Truth ZP: {e}")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    if gt_zp is None:
        return {"passed": False, "score": 0, "feedback": "Ground truth missing; setup failed."}

    # Criterion 1: Measurement file
    meas_exists = result.get('measurement_file_exists', False)
    meas_created = result.get('measurement_file_created_during_task', False)
    if meas_exists and meas_created:
        score += 15
        feedback_parts.append("Measurement file created")
    elif meas_exists:
        score += 5
        feedback_parts.append("Measurement file exists but not newly created")
    else:
        feedback_parts.append("Measurement file missing")

    # Criterion 2: Report file
    report_exists = result.get('report_exists', False)
    report_created = result.get('report_created_during_task', False)
    report_content = result.get('report_content', '')
    
    if report_exists and report_created:
        score += 10
        feedback_parts.append("Report file created")
    elif report_exists:
        score += 3
        feedback_parts.append("Report file exists but not newly created")
    else:
        feedback_parts.append("Report file missing")

    # Criterion 3: Accuracy
    accuracy_score = 0
    reported_zp = None
    
    if report_content:
        # Extract all floating point numbers from the report content
        numbers = re.findall(r"[-+]?\d*\.\d+|\d+", report_content)
        
        best_diff = float('inf')
        for n_str in numbers:
            try:
                val = float(n_str)
                # Ensure the number is somewhat in the range of a typical magnitude ZP
                if 20.0 <= val <= 35.0:
                    diff = abs(val - gt_zp)
                    if diff < best_diff:
                        best_diff = diff
                        reported_zp = val
            except ValueError:
                continue
                
        if reported_zp is not None:
            if best_diff <= 0.1:
                accuracy_score = 40
                feedback_parts.append(f"ZP highly accurate: {reported_zp:.2f} (GT: {gt_zp:.2f})")
            elif best_diff <= 0.3:
                accuracy_score = 20
                feedback_parts.append(f"ZP partially accurate: {reported_zp:.2f} (GT: {gt_zp:.2f})")
            else:
                feedback_parts.append(f"ZP inaccurate: {reported_zp:.2f} (GT: {gt_zp:.2f})")
        else:
            feedback_parts.append("No valid ZP value found in report")
            
    score += accuracy_score

    # Criterion 4: VLM Verification
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            try:
                vlm_resp = query_vlm(prompt=VLM_PROMPT, images=frames)
                if vlm_resp.get("success"):
                    parsed = vlm_resp.get("parsed", {})
                    if parsed.get("photometry_actively_performed"):
                        vlm_score = 35
                        feedback_parts.append("VLM verified photometry workflow")
                    else:
                        feedback_parts.append("VLM did not detect photometry workflow")
                else:
                    feedback_parts.append("VLM query failed")
            except Exception as e:
                feedback_parts.append(f"VLM error: {e}")
        else:
            feedback_parts.append("No trajectory frames for VLM")
    
    score += vlm_score

    # Final logic
    # Pass requires a good ZP accuracy and VLM confirmation
    passed = (score >= 70) and (accuracy_score >= 20) and (vlm_score > 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }