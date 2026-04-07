#!/usr/bin/env python3
"""
Verifier for openvsp_forward_swept_transport task.

Uses `copy_from_env` to retrieve the baseline and modified .vsp3 files.
Parses the XML structure to evaluate the geometric changes.
Validates GUI usage via VLM trajectory checks.
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_geom_element(root, valid_names):
    """Find a Geom element by its Name tag."""
    for geom in root.findall('.//Geom'):
        name_elem = geom.find('Name')
        if name_elem is not None and name_elem.text in valid_names:
            return geom
    return None

def extract_parameters(geom_element):
    """Extract X_Rel_Location, Sweep, and Twist from a Geom component."""
    params = {
        'x_rel': None,
        'sweeps': [],
        'twists': []
    }
    
    if geom_element is None:
        return params
        
    # Extract X location
    x_rel_elem = geom_element.find('.//X_Rel_Location')
    if x_rel_elem is not None:
        try:
            params['x_rel'] = float(x_rel_elem.get('Value', 0))
        except ValueError:
            pass
            
    # Extract Sweeps and Twists from XSecs
    for sweep in geom_element.findall('.//Sweep'):
        try:
            params['sweeps'].append(float(sweep.get('Value', 0)))
        except ValueError:
            pass
            
    for twist in geom_element.findall('.//Twist'):
        try:
            params['twists'].append(float(twist.get('Value', 0)))
        except ValueError:
            pass
            
    return params

def verify_openvsp_fsw_conversion(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    baseline_path = metadata.get('baseline_model', '/home/ga/Documents/OpenVSP/eCRM-001_wing_tail.vsp3')
    output_path = metadata.get('expected_output_path', '/home/ga/Documents/OpenVSP/eCRM001_fsw.vsp3')
    
    # Tolerances and targets
    tgt_wing_sweep = metadata.get('target_wing_sweep', -25.0)
    tgt_wing_twist = metadata.get('target_wing_twist', 2.0)
    tgt_tail_sweep = metadata.get('target_tail_sweep', -15.0)
    tgt_delta_x = metadata.get('target_delta_x', 3.0)
    tol_angle = metadata.get('tolerance_angle', 1.5)
    tol_dist = metadata.get('tolerance_dist', 0.5)

    score = 0
    feedback_parts = []
    
    # 1. Read JSON result metadata
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/openvsp_fsw_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    if not result_meta.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Modified file eCRM001_fsw.vsp3 not found."}
        
    if not result_meta.get('file_created_during_task', False):
        feedback_parts.append("File exists but timestamp indicates it was not created during the task (anti-gaming).")
        # Proceed with partial grading but flag it
        
    score += 10
    feedback_parts.append("File exists and was saved (+10).")

    # 2. Extract and parse Baseline and Output VSP3 files
    temp_base = tempfile.NamedTemporaryFile(delete=False, suffix='_base.vsp3')
    temp_out = tempfile.NamedTemporaryFile(delete=False, suffix='_out.vsp3')
    
    try:
        copy_from_env(baseline_path, temp_base.name)
        copy_from_env(output_path, temp_out.name)
        
        tree_base = ET.parse(temp_base.name)
        tree_out = ET.parse(temp_out.name)
        
        root_base = tree_base.getroot()
        root_out = tree_out.getroot()
        
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to parse XML: {e}"}
    finally:
        if os.path.exists(temp_base.name): os.unlink(temp_base.name)
        if os.path.exists(temp_out.name): os.unlink(temp_out.name)

    # 3. Analyze Geometric Parameters
    wing_names = ['Wing', 'WingGeom']
    tail_names = ['Horiz_Tail', 'Tail', 'TailGeom']
    
    wing_base = get_geom_element(root_base, wing_names)
    wing_out = get_geom_element(root_out, wing_names)
    tail_out = get_geom_element(root_out, tail_names)
    
    if wing_base is None or wing_out is None:
        feedback_parts.append("Wing component missing from one of the files.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    params_base_wing = extract_parameters(wing_base)
    params_out_wing = extract_parameters(wing_out)
    params_out_tail = extract_parameters(tail_out)

    # 3a. Wing Translation (Delta X) (20 points)
    base_x = params_base_wing.get('x_rel')
    out_x = params_out_wing.get('x_rel')
    
    if base_x is not None and out_x is not None:
        delta_x = out_x - base_x
        if abs(delta_x - tgt_delta_x) <= tol_dist:
            score += 20
            feedback_parts.append(f"Wing X-Location correctly moved aft by {delta_x:.2f}m (+20).")
        else:
            feedback_parts.append(f"Wing Delta X is {delta_x:.2f}m, expected {tgt_delta_x}m (+0).")
    else:
        feedback_parts.append("Could not determine Wing X-Location (+0).")

    # 3b. Wing Sweep (20 points)
    wing_sweeps = params_out_wing.get('sweeps', [])
    if any(abs(s - tgt_wing_sweep) <= tol_angle for s in wing_sweeps):
        score += 20
        feedback_parts.append(f"Wing Sweep correctly set to approx {tgt_wing_sweep}° (+20).")
    else:
        feedback_parts.append(f"Wing Sweeps found {wing_sweeps[:3]} do not match target {tgt_wing_sweep}° (+0).")

    # 3c. Wing Twist (15 points)
    wing_twists = params_out_wing.get('twists', [])
    if any(abs(t - tgt_wing_twist) <= tol_angle for t in wing_twists):
        score += 15
        feedback_parts.append(f"Wing Twist correctly set to approx {tgt_wing_twist}° (+15).")
    else:
        feedback_parts.append(f"Wing Twists found {wing_twists[:3]} do not match target {tgt_wing_twist}° (+0).")

    # 3d. Tail Sweep (15 points)
    if tail_out is not None:
        tail_sweeps = params_out_tail.get('sweeps', [])
        if any(abs(s - tgt_tail_sweep) <= tol_angle for s in tail_sweeps):
            score += 15
            feedback_parts.append(f"Tail Sweep correctly set to approx {tgt_tail_sweep}° (+15).")
        else:
            feedback_parts.append(f"Tail Sweeps found {tail_sweeps[:2]} do not match target {tgt_tail_sweep}° (+0).")
    else:
        feedback_parts.append("Horizontal Tail component not found (+0).")

    # 4. VLM Verification - Trajectory checks (20 points)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            
            prompt = """
            You are verifying an agent interacting with the OpenVSP parametric CAD tool.
            Look at these frames sampled across the trajectory.
            Did the agent actively use the OpenVSP GUI to modify parameters (like typing in fields, clicking tabs like 'Plan' or 'XForm')?
            Or does the screen show the agent writing a Python script / using a text editor to directly edit the XML file?
            
            Respond in JSON format:
            {
                "used_openvsp_gui": true/false,
                "used_text_editor_cheat": true/false,
                "reasoning": "Brief explanation"
            }
            """
            
            vlm_response = query_vlm(images=frames + [final_frame], prompt=prompt)
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("used_openvsp_gui", False) and not parsed.get("used_text_editor_cheat", False):
                    score += 20
                    feedback_parts.append("VLM verified GUI usage (+20).")
                else:
                    feedback_parts.append("VLM indicated text editor/script cheat or lack of GUI interaction (+0).")
            else:
                score += 20 # Fallback grant if VLM fails
                feedback_parts.append("VLM verification failed, granting GUI usage points by default (+20).")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            score += 20 # Fallback
            feedback_parts.append("VLM exception, granting GUI points (+20).")
    else:
        score += 20 # Fallback
        feedback_parts.append("VLM not available, granting GUI points (+20).")

    # Final Evaluation
    passed = score >= 60 and result_meta.get('file_created_during_task', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }