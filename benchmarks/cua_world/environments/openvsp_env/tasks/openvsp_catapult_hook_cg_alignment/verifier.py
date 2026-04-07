#!/usr/bin/env python3
"""
Verifier for openvsp_catapult_hook_cg_alignment task.
"""

import json
import os
import re
import tempfile
import xml.etree.ElementTree as ET

def verify_openvsp_catapult_hook(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    if not result.get('model_exists'):
        return {"passed": False, "score": 0, "feedback": "uav_launch_ready.vsp3 not saved."}

    score += 10
    feedback.append("Model file saved.")

    # Try to extract X_cg from MassProps file
    actual_cg = None
    if result.get('massprops_exists'):
        score += 10
        feedback.append("tactical_uav_MassProps.txt generated.")
        massprops_content = result.get('massprops_content', '')
        for line in massprops_content.splitlines():
            if 'CG' in line.upper() or 'C.G.' in line.upper():
                m = re.search(r'X\s*[:=]?\s*([+-]?\d+\.\d+)', line, re.IGNORECASE)
                if m:
                    actual_cg = float(m.group(1))
                    break
        if actual_cg is None:
            m = re.search(r'X_?cg\s*[:=]?\s*([+-]?\d+\.\d+)', massprops_content, re.IGNORECASE)
            if m:
                actual_cg = float(m.group(1))
    else:
        feedback.append("tactical_uav_MassProps.txt not found - agent might not have run analysis.")

    # Find LaunchHook in XML
    model_content = result.get('model_content', '')
    try:
        root = ET.fromstring(model_content)
    except Exception:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback) + " | Model XML is invalid."}

    hook_geom = None
    for geom in root.findall(".//Geom"):
        name_elem = geom.find("Name")
        if name_elem is not None and "launchhook" in name_elem.text.lower():
            hook_geom = geom
            break

    if not hook_geom:
        feedback.append("LaunchHook component not found.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    score += 20
    feedback.append("LaunchHook component created.")

    geom_str = ET.tostring(hook_geom).decode('utf-8')

    m_len = re.search(r'<Length\s+Value="([^"]+)"', geom_str)
    length = float(m_len.group(1)) if m_len else None

    m_x = re.search(r'<X_Rel_Location\s+Value="([^"]+)"', geom_str)
    x_loc = float(m_x.group(1)) if m_x else None

    m_z = re.search(r'<Z_Rel_Location\s+Value="([^"]+)"', geom_str)
    z_loc = float(m_z.group(1)) if m_z else None

    if length is not None and abs(length - 0.15) < 0.02:
        score += 15
        feedback.append("Length correct.")
    else:
        feedback.append(f"Length incorrect or not found: {length}")

    if z_loc is not None and abs(z_loc - (-0.3)) < 0.02:
        score += 15
        feedback.append("Z Location correct.")
    else:
        feedback.append(f"Z Location incorrect or not found: {z_loc}")

    if x_loc is not None:
        if actual_cg is not None and abs(x_loc - actual_cg) < 0.02:
            score += 30
            feedback.append(f"X Location ({x_loc:.3f}) matches computed CG ({actual_cg:.3f}).")
        elif actual_cg is None:
            feedback.append(f"X Location set to {x_loc:.3f}, but CG could not be verified from MassProps file.")
        else:
            feedback.append(f"X Location ({x_loc:.3f}) does NOT match computed CG ({actual_cg:.3f}).")

    passed = score >= 70
    return {"passed": passed, "score": score, "feedback": " | ".join(feedback)}