#!/usr/bin/env python3
"""
Verifier for openvsp_inlet_diffuser_loft task.

Verifies:
1. Model file created during the task.
2. Contains a component named "Ramjet_Inlet".
3. Overall length is ~4.5m.
4. Front cross-section is ~0.8m x 0.4m.
5. Rear cross-section is ~0.7m x 0.7m.
6. Report calculates the area ratio ~1.203.
7. VLM check on trajectory to confirm work in OpenVSP.
"""

import json
import os
import re
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants based on task spec
EXPECTED_LENGTH = 4.5
FRONT_W, FRONT_H = 0.8, 0.4
REAR_W, REAR_H = 0.7, 0.7
AREA_RATIO_MIN, AREA_RATIO_MAX = 1.18, 1.22
TOLERANCE = 0.05

VLM_PROMPT = """You are verifying if a computer agent successfully created a 3D model of an inlet diffuser in OpenVSP.

TASK: Create a lofted Duct transitioning from a rectangular front to a circular rear.

Look at these trajectory frames and the final screenshot:
1. Did the agent open and use OpenVSP?
2. Did the agent manipulate cross sections (XSecs) to create a shape that is rectangular on one end and circular on the other?
3. Is a 3D model visible in the workspace that resembles a duct or fuselage?

Respond ONLY in valid JSON format:
{
    "used_openvsp": true/false,
    "manipulated_xsec": true/false,
    "3d_model_visible": true/false,
    "confidence": "low/medium/high"
}
"""

def extract_val(xsec_element, param_names):
    """Helper to extract a float value for a parameter from an XSec XML element."""
    for p in xsec_element.findall('.//Parm'):
        if p.get('Name') in param_names:
            try:
                return float(p.get('Value'))
            except ValueError:
                pass
    return None

def verify_openvsp_inlet_diffuser_loft(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    result_file = "/tmp/openvsp_inlet_result.json"
    local_tmp = tempfile.mktemp(suffix=".json")
    
    try:
        copy_from_env(result_file, local_tmp)
        with open(local_tmp, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load exported result: {e}"}
    finally:
        if os.path.exists(local_tmp):
            os.unlink(local_tmp)

    score = 0
    feedback_parts = []
    
    # Check timestamps for anti-gaming
    task_start = data.get('task_start_time', 0)
    model_mtime = data.get('model_mtime', 0)
    
    # --- Criterion 1: Model Exists (10 pts) ---
    if not data.get('model_exists'):
        feedback_parts.append("Model ramjet_inlet.vsp3 not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    
    if model_mtime >= task_start:
        score += 10
        feedback_parts.append("Model saved during task (+10)")
    else:
        feedback_parts.append("Model existed before task and was not modified (+0)")

    # --- Parse XML ---
    content = data.get('model_content', '')
    target_geom = None
    try:
        root = ET.fromstring(content)
        geoms = root.findall('.//Geom')
        
        # --- Criterion 2: Component Name (10 pts) ---
        for geom in geoms:
            name_parm = geom.find('.//Parm[@Name="Name"]')
            if name_parm is not None and name_parm.get('Value') == 'Ramjet_Inlet':
                target_geom = geom
                break
        
        if target_geom is not None:
            score += 10
            feedback_parts.append("Component 'Ramjet_Inlet' found (+10)")
        elif geoms:
            # Fallback to the first non-default Geom if name is slightly off
            target_geom = geoms[0]
            feedback_parts.append("Component 'Ramjet_Inlet' not found exactly, evaluating first component (+0)")
        else:
            feedback_parts.append("No geometry components found in file (+0)")
            
    except ET.ParseError as e:
        feedback_parts.append(f"Model is not valid XML: {e}")
        
    if target_geom is not None:
        # --- Criterion 3: Length (10 pts) ---
        length_parm = target_geom.find('.//Parm[@Name="Length"]')
        if length_parm is not None:
            try:
                length_val = float(length_parm.get('Value'))
                if abs(length_val - EXPECTED_LENGTH) <= TOLERANCE:
                    score += 10
                    feedback_parts.append(f"Length correct ({length_val:.2f}m) (+10)")
                else:
                    feedback_parts.append(f"Length incorrect ({length_val:.2f}m != 4.5m)")
            except ValueError:
                feedback_parts.append("Invalid Length parameter")
        else:
            feedback_parts.append("Length parameter not found")

        # --- Criterion 4 & 5: XSec dimensions (30 pts total) ---
        xsecs = target_geom.findall('.//XSecSurf/XSec')
        if len(xsecs) >= 2:
            front_xsec = xsecs[0]
            rear_xsec = xsecs[-1]
            
            # Front XSec (15 pts)
            fw = extract_val(front_xsec, ['Width', 'DesignWidth'])
            fh = extract_val(front_xsec, ['Height', 'DesignHeight'])
            if fw is not None and fh is not None:
                if abs(fw - FRONT_W) <= TOLERANCE and abs(fh - FRONT_H) <= TOLERANCE:
                    score += 15
                    feedback_parts.append(f"Front XSec correct ({fw:.2f}x{fh:.2f}) (+15)")
                else:
                    feedback_parts.append(f"Front XSec incorrect ({fw:.2f}x{fh:.2f} != 0.8x0.4)")
            else:
                feedback_parts.append("Could not extract Front XSec dimensions")
                
            # Rear XSec (15 pts)
            rw = extract_val(rear_xsec, ['Width', 'DesignWidth'])
            rh = extract_val(rear_xsec, ['Height', 'DesignHeight'])
            if rw is not None and rh is not None:
                if abs(rw - REAR_W) <= TOLERANCE and abs(rh - REAR_H) <= TOLERANCE:
                    score += 15
                    feedback_parts.append(f"Rear XSec correct ({rw:.2f}x{rh:.2f}) (+15)")
                else:
                    feedback_parts.append(f"Rear XSec incorrect ({rw:.2f}x{rh:.2f} != 0.7x0.7)")
            else:
                feedback_parts.append("Could not extract Rear XSec dimensions")
        else:
            feedback_parts.append("Insufficient cross-sections found")

    # --- Criterion 6: Report and Calculation (10 pts) ---
    if data.get('report_exists'):
        report_content = data.get('report_content', '')
        
        # Look for the ratio in the text
        ratio_found = False
        numbers = re.findall(r'[+-]?\d+\.?\d*', report_content)
        for n in numbers:
            try:
                v = float(n)
                if AREA_RATIO_MIN <= v <= AREA_RATIO_MAX:
                    score += 10
                    feedback_parts.append(f"Correct area ratio found in report: {v} (+10)")
                    ratio_found = True
                    break
            except ValueError:
                pass
        
        if not ratio_found:
            feedback_parts.append("Report exists but correct area ratio (~1.20) not found")
    else:
        feedback_parts.append("Report diffuser_report.txt not found")

    # --- Criterion 7: VLM Trajectory Verification (30 pts) ---
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            vlm_result = query_vlm(prompt=VLM_PROMPT, images=images)
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                vlm_score = 0
                if parsed.get("used_openvsp"): vlm_score += 10
                if parsed.get("manipulated_xsec"): vlm_score += 10
                if parsed.get("3d_model_visible"): vlm_score += 10
                
                # Confidence multiplier
                conf = parsed.get("confidence", "low").lower()
                mult = 1.0 if conf == "high" else (0.8 if conf == "medium" else 0.5)
                final_vlm_score = int(vlm_score * mult)
                
                score += final_vlm_score
                feedback_parts.append(f"VLM verification scored {final_vlm_score}/30")
            else:
                feedback_parts.append("VLM query failed, skipping VLM points")
        else:
            feedback_parts.append("No screenshots available for VLM")
    else:
        feedback_parts.append("VLM query function not available")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }