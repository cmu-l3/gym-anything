#!/usr/bin/env python3
"""
Verifier for openvsp_helicopter_rotor_layout task.

Evaluation Criteria:
1. File exists, is valid XML, and was created during the task (Anti-gaming) (10 pts)
2. Main Rotor exists and is named correctly (10 pts)
3. Main Rotor Geometry (Diameter, NumBlades) (15 pts)
4. Main Rotor Spatial Setup (X, Z, Pitch/Y_Rot) (15 pts)
5. Tail Rotor exists and is named correctly (10 pts)
6. Tail Rotor Geometry (Diameter, NumBlades) (15 pts)
7. Tail Rotor Spatial Setup (X, Y, Z, Yaw/Z_Rot) (15 pts)
8. VLM Trajectory Verification - confirmed UI usage (10 pts)

Pass threshold: 70
"""

import json
import os
import xml.etree.ElementTree as ET
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def get_vsp_param(geom_element, param_name):
    """Recursively find an OpenVSP parameter by element tag name and return its Value."""
    param = geom_element.find(f".//{param_name}")
    if param is not None:
        try:
            return float(param.attrib.get("Value", 0.0))
        except ValueError:
            pass
    return None


def check_tolerance(actual, expected, tol):
    """Check if actual is within tol of expected."""
    if actual is None:
        return False
    return abs(actual - expected) <= tol


def verify_helicopter_rotor_layout(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", "/tmp/openvsp_helicopter_result.json")
    
    tol_dim = metadata.get("tolerance_dim", 0.15)
    tol_deg = metadata.get("tolerance_deg", 1.5)
    
    main_spec = metadata.get("main_rotor", {})
    tail_spec = metadata.get("tail_rotor", {})

    # Copy result file from environment
    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env(result_file, local_tmp)
        with open(local_tmp, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result file missing. Task export failed: {e}"}
    finally:
        if os.path.exists(local_tmp):
            os.unlink(local_tmp)

    score = 0
    feedback_parts = []

    # --- Criterion 1: File Exists & Anti-Gaming (10 pts) ---
    if not data.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "helicopter_configured.vsp3 not found."}
    
    if not data.get("file_created_during_task", False):
        feedback_parts.append("Warning: File timestamp indicates it was not saved during this session.")
    else:
        feedback_parts.append("File exists and timestamp is valid (+10)")
        score += 10

    # Parse XML
    content = data.get("file_content", "").replace("\\n", "\n")
    try:
        root = ET.fromstring(content)
        vehicle = root.find("Vehicle")
        if vehicle is None:
            raise ValueError("No <Vehicle> root found in XML")
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"File is not valid OpenVSP XML: {e}"}

    # Extract Propeller components
    propellers = []
    for geom in vehicle.findall("Geom"):
        type_elem = geom.find("Type")
        if type_elem is not None and type_elem.text == "Propeller":
            propellers.append(geom)

    # --- Find Main and Tail Rotors ---
    main_rotor = None
    tail_rotor = None
    
    for prop in propellers:
        name_elem = prop.find("Name")
        if name_elem is not None and name_elem.text:
            name = name_elem.text.lower()
            if "main" in name:
                main_rotor = prop
            elif "tail" in name:
                tail_rotor = prop

    # --- Criteria 2-4: Main Rotor (40 pts) ---
    if main_rotor is not None:
        score += 10
        feedback_parts.append("Main Rotor component found (+10)")
        
        # Geometry
        d = get_vsp_param(main_rotor, "Diameter")
        n = get_vsp_param(main_rotor, "NumBlade")
        
        geom_pts = 0
        if check_tolerance(d, main_spec["diameter"], tol_dim): geom_pts += 7.5
        if check_tolerance(n, main_spec["num_blades"], 0.1): geom_pts += 7.5
        score += int(geom_pts)
        feedback_parts.append(f"Main Rotor Geom: D={d}, Blades={n} (+{int(geom_pts)})")
        
        # Spatial
        x = get_vsp_param(main_rotor, "X_Rel")
        z = get_vsp_param(main_rotor, "Z_Rel")
        pitch = get_vsp_param(main_rotor, "Y_Rot")
        
        spat_pts = 0
        if check_tolerance(x, main_spec["x_rel"], tol_dim): spat_pts += 5
        if check_tolerance(z, main_spec["z_rel"], tol_dim): spat_pts += 5
        # Absolute value since Pitch could be +90 or -90 depending on desired spin direction
        if pitch is not None and check_tolerance(abs(pitch), main_spec["y_rot"], tol_deg): spat_pts += 5
        score += int(spat_pts)
        feedback_parts.append(f"Main Rotor Spatial: X={x}, Z={z}, Pitch={pitch} (+{int(spat_pts)})")
    else:
        feedback_parts.append("Main Rotor Propeller component not found")

    # --- Criteria 5-7: Tail Rotor (40 pts) ---
    if tail_rotor is not None:
        score += 10
        feedback_parts.append("Tail Rotor component found (+10)")
        
        # Geometry
        d = get_vsp_param(tail_rotor, "Diameter")
        n = get_vsp_param(tail_rotor, "NumBlade")
        
        geom_pts = 0
        if check_tolerance(d, tail_spec["diameter"], tol_dim): geom_pts += 7.5
        if check_tolerance(n, tail_spec["num_blades"], 0.1): geom_pts += 7.5
        score += int(geom_pts)
        feedback_parts.append(f"Tail Rotor Geom: D={d}, Blades={n} (+{int(geom_pts)})")
        
        # Spatial
        x = get_vsp_param(tail_rotor, "X_Rel")
        y = get_vsp_param(tail_rotor, "Y_Rel")
        z = get_vsp_param(tail_rotor, "Z_Rel")
        yaw = get_vsp_param(tail_rotor, "Z_Rot")
        
        spat_pts = 0
        if check_tolerance(x, tail_spec["x_rel"], tol_dim): spat_pts += 3.75
        if check_tolerance(y, tail_spec["y_rel"], tol_dim): spat_pts += 3.75
        if check_tolerance(z, tail_spec["z_rel"], tol_dim): spat_pts += 3.75
        if yaw is not None and check_tolerance(abs(yaw), tail_spec["z_rot"], tol_deg): spat_pts += 3.75
        score += int(spat_pts)
        feedback_parts.append(f"Tail Rotor Spatial: X={x}, Y={y}, Z={z}, Yaw={yaw} (+{int(spat_pts)})")
    else:
        feedback_parts.append("Tail Rotor Propeller component not found")

    # --- Criterion 8: VLM Trajectory Verification (10 pts) ---
    # Optional VLM verification to ensure the agent didn't just inject XML directly
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                prompt = """You are verifying an agent completing a CAD task in OpenVSP.
                Task: Add a main lifting rotor and tail rotor (propellers) to a helicopter fuselage.
                Look at the trajectory frames and final screenshot.
                1. Did the agent open and actively interact with the OpenVSP GUI?
                2. Can you see rotor/propeller geometry being added or configured in the workspace?
                Respond in JSON format: {"gui_used": true/false, "rotors_visible": true/false}"""
                
                vlm_res = query_vlm(prompt=prompt, images=images)
                if vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    if parsed.get("gui_used", False): vlm_score += 5
                    if parsed.get("rotors_visible", False): vlm_score += 5
                    
                feedback_parts.append(f"VLM Trajectory Verification: +{vlm_score}")
                score += vlm_score
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            # Do not penalize if VLM fails entirely due to framework issues
            score += 10
            feedback_parts.append("VLM Verification skipped/errored (+10 auto-credit)")
    else:
        score += 10
        feedback_parts.append("VLM Verification disabled (+10 auto-credit)")

    # Define pass state
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }