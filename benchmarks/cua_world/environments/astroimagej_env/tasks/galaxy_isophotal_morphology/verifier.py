#!/usr/bin/env python3
"""
Verifier for Isophotal Galaxy Morphology Measurement.

This verifier checks:
1. Dynamic background stats vs agent's report
2. Accuracy of the T = Mean + 3*StdDev calculation
3. Region properties (Major, Minor, Ellipticity) vs dynamically generated ground truth
4. Existence of the CSV and UI visual interaction via VLM
"""

import os
import re
import json
import tempfile
import logging
from typing import Dict, Any
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying that an agent successfully used AstroImageJ to measure a galaxy.

Review these trajectory frames and determine if:
1. An astronomical image (galaxy) was opened.
2. The "Threshold" tool was used (you might see a red overlay on the image isolating the galaxy, or the Threshold dialog window).
3. The Particle Analyzer was used (you will see the "Results" table with columns like Major, Minor, Angle).

Respond in JSON format:
{
    "image_opened": true/false,
    "threshold_tool_used": true/false,
    "particle_results_visible": true/false
}
"""

def verify_galaxy_morphology(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback = []
    
    # --- Load Result Data ---
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read task_result.json: {e}"}
    finally:
        if os.path.exists(temp.name): os.unlink(temp.name)

    # --- Load Ground Truth ---
    try:
        temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/galaxy_gt.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read ground truth: {e}"}
    finally:
        if os.path.exists(temp_gt.name): os.unlink(temp_gt.name)

    # --- Load Agent Report ---
    report_content = ""
    if result.get("report_copied"):
        try:
            temp_rep = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            copy_from_env("/tmp/agent_morphology_report.txt", temp_rep.name)
            with open(temp_rep.name, 'r') as f:
                report_content = f.read()
        except Exception as e:
            logger.warning(f"Could not read agent report: {e}")
        finally:
            if os.path.exists(temp_rep.name): os.unlink(temp_rep.name)

    if not report_content:
        return {"passed": False, "score": 0, "feedback": "Agent morphology_report.txt missing or empty."}

    # --- Parse Agent Report ---
    def extract_val(pattern):
        match = re.search(pattern, report_content, re.IGNORECASE)
        return float(match.group(1)) if match else None

    agent_mean = extract_val(r'BACKGROUND_MEAN:\s*([-+]?[0-9]*\.?[0-9]+)')
    agent_std = extract_val(r'BACKGROUND_STDDEV:\s*([-+]?[0-9]*\.?[0-9]+)')
    agent_thresh = extract_val(r'ISOPHOTAL_THRESHOLD:\s*([-+]?[0-9]*\.?[0-9]+)')
    agent_major = extract_val(r'MAJOR_AXIS:\s*([-+]?[0-9]*\.?[0-9]+)')
    agent_minor = extract_val(r'MINOR_AXIS:\s*([-+]?[0-9]*\.?[0-9]+)')
    agent_ellip = extract_val(r'ELLIPTICITY:\s*([-+]?[0-9]*\.?[0-9]+)')

    # --- Criterion 1: Background Stats (20 pts) ---
    if agent_mean is not None and agent_std is not None:
        mean_diff = abs(agent_mean - gt["bg_mean"]) / max(abs(gt["bg_mean"]), 1)
        std_diff = abs(agent_std - gt["bg_std"]) / max(abs(gt["bg_std"]), 1)
        
        # We allow a slightly wider tolerance because exact manual ROI placement can vary by a pixel
        if mean_diff < 0.15 and std_diff < 0.20:
            score += 20
            feedback.append("Background mean & stddev within tolerance.")
        elif mean_diff < 0.30 and std_diff < 0.40:
            score += 10
            feedback.append("Background stats approximate (placed ROI slightly off target).")
        else:
            feedback.append(f"Background stats out of bounds (Got Mean: {agent_mean}, Std: {agent_std}).")
    else:
        feedback.append("Background stats missing from report.")

    # --- Criterion 2: Threshold Calculation (15 pts) ---
    if agent_mean is not None and agent_std is not None and agent_thresh is not None:
        expected_calc = agent_mean + (3.0 * agent_std)
        if abs(agent_thresh - expected_calc) < 0.1:
            score += 15
            feedback.append("Isophotal threshold correctly calculated mathematically.")
        else:
            feedback.append(f"Threshold calculation incorrect. Expected {expected_calc:.2f}, got {agent_thresh}.")
    else:
        feedback.append("Threshold values missing from report.")

    # --- Criterion 3: Morphology Accuracy (30 pts) ---
    if agent_major is not None and agent_minor is not None:
        major_diff = abs(agent_major - gt["major"]) / max(gt["major"], 1)
        minor_diff = abs(agent_minor - gt["minor"]) / max(gt["minor"], 1)
        
        if major_diff < 0.15 and minor_diff < 0.15:
            score += 30
            feedback.append("Major and Minor axes highly accurate.")
        elif major_diff < 0.30 and minor_diff < 0.30:
            score += 15
            feedback.append("Major and Minor axes approximate (likely threshold rounding).")
        else:
            feedback.append(f"Morphology measurements significantly off (Major: {agent_major}, Minor: {agent_minor}).")
    else:
        feedback.append("Major or Minor axis missing from report.")

    # --- Criterion 4: Ellipticity Calculation (10 pts) ---
    if agent_major is not None and agent_minor is not None and agent_ellip is not None and agent_major > 0:
        expected_ellip = 1.0 - (agent_minor / agent_major)
        if abs(agent_ellip - expected_ellip) < 0.05:
            score += 10
            feedback.append("Ellipticity correctly derived from axes.")
        else:
            feedback.append(f"Ellipticity miscalculated. Expected {expected_ellip:.3f}, got {agent_ellip}.")

    # --- Criterion 5: CSV Export (10 pts) ---
    if result.get("csv_exists"):
        score += 10
        feedback.append("CSV measurement export found.")
    else:
        feedback.append("galaxy_morphology.csv not found.")

    # --- Criterion 6: VLM Trajectory (15 pts) ---
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            vlm_res = query_vlm(prompt=VLM_PROMPT, images=frames)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("threshold_tool_used") and parsed.get("particle_results_visible"):
                    score += 15
                    feedback.append("VLM confirmed use of Threshold and Particle Analyzer UI.")
                else:
                    feedback.append("VLM did not detect full UI workflow progression.")
            else:
                feedback.append("VLM evaluation failed.")
    
    passed = score >= 70 and result.get("csv_exists", False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "agent_report": report_content,
            "ground_truth": gt
        }
    }