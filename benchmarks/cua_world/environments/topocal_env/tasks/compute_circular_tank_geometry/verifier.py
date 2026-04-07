#!/usr/bin/env python3
"""
Verifier for compute_circular_tank_geometry task.

Verification Strategy:
1. Validates presence and anti-gaming timestamp of `tank_geometry.txt`.
2. Parses text output for CenterX, CenterY, and Radius.
3. Compares extracted values against perfectly mathematical ground truth.
4. Uses strict 0.05m tolerance: proves the agent used exact CAD object snaps
   rather than free-hand approximations.
5. Verifies structural creation of final CAD files and uses VLM verification 
   of trajectory to ensure proper tool usage inside TopoCal.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compute_circular_tank_geometry(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available in environment."}

    # Extract ground truth metadata
    meta = task_info.get('metadata', {})
    gt_x = meta.get('ground_truth_x', 2400.0)
    gt_y = meta.get('ground_truth_y', 3100.0)
    gt_r = meta.get('ground_truth_radius', 25.0)
    tolerance = meta.get('tolerance', 0.05)

    # Copy exported result bundle from the Windows container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/Users/Docker/Documents/task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result state: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    cad_saved = result.get('cad_saved', False)
    modified_during_task = result.get('report_modified_during_task', False)

    # ANTI-GAMING: Check if file was created before task
    if report_exists and not modified_during_task:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Report file exists but was not modified during the task (Failed anti-gaming check)."
        }

    # --- CRITERION: Exact Mathematical Output (60 pts) ---
    if report_exists:
        score += 10
        feedback.append("Report file correctly generated.")

        # Robust regex for property extraction
        x_match = re.search(r'Center[\s_]*X[\s:=]+([-+]?[0-9]*\.?[0-9]+)', report_content, re.IGNORECASE)
        y_match = re.search(r'Center[\s_]*Y[\s:=]+([-+]?[0-9]*\.?[0-9]+)', report_content, re.IGNORECASE)
        r_match = re.search(r'Radius[\s:=]+([-+]?[0-9]*\.?[0-9]+)', report_content, re.IGNORECASE)

        if x_match:
            x_val = float(x_match.group(1))
            if abs(x_val - gt_x) <= tolerance:
                score += 15
                feedback.append(f"Center X accurate ({x_val}).")
            else:
                feedback.append(f"Center X inaccurate: {x_val} (Expected {gt_x}).")
        else:
            feedback.append("Center X not found in report.")

        if y_match:
            y_val = float(y_match.group(1))
            if abs(y_val - gt_y) <= tolerance:
                score += 15
                feedback.append(f"Center Y accurate ({y_val}).")
            else:
                feedback.append(f"Center Y inaccurate: {y_val} (Expected {gt_y}).")
        else:
            feedback.append("Center Y not found in report.")

        if r_match:
            r_val = float(r_match.group(1))
            if abs(r_val - gt_r) <= tolerance:
                score += 20
                feedback.append(f"Radius accurate ({r_val}).")
            else:
                feedback.append(f"Radius inaccurate: {r_val} (Expected {gt_r}).")
        else:
            feedback.append("Radius not found in report.")
    else:
        feedback.append("Report file missing.")

    # --- CRITERION: Deliverables Exists (10 pts) ---
    if cad_saved:
        score += 10
        feedback.append("CAD export model saved.")
    else:
        feedback.append("CAD model export missing.")

    # --- CRITERION: VLM Trajectory (30 pts) ---
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames

            prompt = (
                "You are evaluating a user completing a CAD task in TopoCal. "
                "Looking at these screenshots across the session, answer:\n"
                "1. Is the TopoCal user interface visible?\n"
                "2. Did the user use the circle drawing tool ('círculo' icon) or is a constructed circle visible?\n"
                "3. Did the user open a properties/information window (Propiedades) showing geometry details?\n"
                "Reply STRICTLY with JSON format: "
                "{\"topocal_visible\": true/false, \"circle_constructed\": true/false, \"properties_opened\": true/false}"
            )
            
            vlm_res = query_vlm(images=images, prompt=prompt)
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('topocal_visible'):
                    vlm_score += 10
                if parsed.get('circle_constructed'):
                    vlm_score += 10
                    feedback.append("VLM Verification: Circle was actively drawn.")
                if parsed.get('properties_opened'):
                    vlm_score += 10
                    feedback.append("VLM Verification: Properties window was opened.")
            else:
                feedback.append("VLM query failed to parse.")
    except Exception as e:
        feedback.append(f"VLM error: {e}")

    score += vlm_score

    # Passing requires high mathematical precision (proving snap) + some process proof
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }