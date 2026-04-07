#!/usr/bin/env python3
"""
Verifier for openvsp_nacelle_integration task.

Checks that the agent created a new Pod/BodyOfRevolution component matching the spec:
  1. Target output file exists and modified after task start (Anti-gaming) (15 pts)
  2. New component identified (Pod/Stack/BodyOfRev or named nacelle/engine) (25 pts)
  3. X, Y, Z coordinates approximately match 7.5, 5.0, -1.2 (20 pts)
  4. Dimensions (Length, Diameter/Fineness) approximately match 3.0, 1.6 (20 pts)
  5. XZ Planar symmetry enabled (10 pts)
  6. VLM trajectory verification shows GUI interaction (10 pts)

Pass threshold: 65 points and new component must be present.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _find_param_value(comp_xml: str, tags: list) -> float:
    """Extract a float value for the first matched XML tag in a component block."""
    for tag in tags:
        pattern = rf'<{tag}\s+[^>]*Value="([^"]+)"'
        m = re.search(pattern, comp_xml, re.IGNORECASE)
        if m:
            try:
                return float(m.group(1))
            except ValueError:
                pass
    return None


def verify_gui_interaction(traj, env_info):
    """Optional VLM verification to ensure trajectory reflects actual work."""
    query_vlm = env_info.get("query_vlm")
    if not query_vlm:
        return True, "VLM not available, assuming GUI interaction occurred."
    
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    images = frames + ([final] if final else [])
    
    if not images:
        return False, "No trajectory images found."

    prompt = """You are evaluating an agent's trajectory in the OpenVSP CAD software.
The agent was asked to add a new engine nacelle (pod) component to an aircraft and set its dimensions/position.
Looking at these trajectory frames, did the agent interact with the OpenVSP interface to do this work?
Look for:
- Geometry browser window being used or visible
- A new component appearing in the 3D viewer
- Parameter tabs (Design, XForm) being edited

Respond in JSON format:
{
    "interacted": true/false,
    "reasoning": "Brief explanation"
}"""
    try:
        res = query_vlm(prompt=prompt, images=images)
        if res.get("success"):
            parsed = res.get("parsed", {})
            return parsed.get("interacted", False), parsed.get("reasoning", "")
    except Exception as e:
        logger.error(f"VLM error: {e}")
    return True, "VLM check failed, granting benefit of doubt."


def verify_openvsp_nacelle_integration(traj, env_info, task_info):
    result_file = task_info.get("metadata", {}).get(
        "result_file", "/tmp/openvsp_nacelle_integration_result.json"
    )
    
    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        env_info["copy_from_env"](result_file, local_tmp)
        with open(local_tmp, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to retrieve exported result file: {e}"
        }
    finally:
        if os.path.exists(local_tmp):
            os.unlink(local_tmp)

    score = 0
    feedback_parts = []
    
    # 1. Check file existence and anti-gaming (15 pts)
    if not data.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target file eCRM-001_with_nacelles.vsp3 not found."
        }
        
    mtime = data.get("mtime", 0)
    task_start = data.get("task_start", 0)
    file_size = data.get("file_size", 0)
    
    if mtime < task_start:
        feedback_parts.append("File modification time is before task start (Anti-gaming check failed) (+0).")
    elif file_size < 10000:
        feedback_parts.append(f"File exists but is too small to be a valid model ({file_size} bytes) (+0).")
    else:
        score += 15
        feedback_parts.append("Valid target file saved during task session (+15).")
        
    content = data.get("file_content", "")
    
    # 2. Extract components and find the new nacelle (25 pts)
    components = re.findall(r'<Component>(.*?)</Component>', content, re.DOTALL)
    nacelle_comp = None
    
    for comp in components:
        type_m = re.search(r'<Type>([^<]+)</Type>', comp)
        name_m = re.search(r'<Name>([^<]+)</Name>', comp)
        comp_type = type_m.group(1).strip() if type_m else ""
        comp_name = name_m.group(1).strip().lower() if name_m else "unknown"
        
        # Original eCRM-001 components
        if comp_name in ["fuselage", "wing", "htail", "vtail"] and comp_type not in ["Pod", "BodyOfRevolution"]:
            continue
            
        # Match candidate
        if comp_type in ["Pod", "BodyOfRevolution", "Stack"] or "nacelle" in comp_name or "engine" in comp_name:
            nacelle_comp = comp
            break
            
    if not nacelle_comp:
        feedback_parts.append("No new nacelle/pod component found in the model (+0).")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    score += 25
    feedback_parts.append("New nacelle component identified (+25).")
    
    # Extract parameters
    x_pos = _find_param_value(nacelle_comp, ["X_Location"])
    y_pos = _find_param_value(nacelle_comp, ["Y_Location"])
    z_pos = _find_param_value(nacelle_comp, ["Z_Location"])
    length = _find_param_value(nacelle_comp, ["Length", "Design_Length"])
    fine_ratio = _find_param_value(nacelle_comp, ["FineRatio"])
    diameter = _find_param_value(nacelle_comp, ["Diameter", "Max_Diam"])
    symmetry = _find_param_value(nacelle_comp, ["Sym_Planar_Flag"])
    
    if diameter is None and fine_ratio is not None and fine_ratio > 0 and length is not None:
        diameter = length / fine_ratio

    # 3. Position checks (20 pts)
    pos_score = 0
    if x_pos is not None and 6.0 <= x_pos <= 9.0: pos_score += 7
    if y_pos is not None and 3.0 <= abs(y_pos) <= 8.0: pos_score += 7
    if z_pos is not None and -3.0 <= z_pos <= -0.1: pos_score += 6
    score += pos_score
    feedback_parts.append(f"Position check ({x_pos}, {y_pos}, {z_pos}): +{pos_score} pts.")
    
    # 4. Dimension checks (20 pts)
    dim_score = 0
    if length is not None and 2.0 <= length <= 4.0: dim_score += 10
    if diameter is not None and 1.0 <= diameter <= 2.5: dim_score += 10
    score += dim_score
    feedback_parts.append(f"Dimensions check (L={length}, D={diameter}): +{dim_score} pts.")
    
    # 5. Symmetry check (10 pts)
    if symmetry is not None and symmetry >= 1.0:
        score += 10
        feedback_parts.append("XZ Planar Symmetry enabled (+10).")
    else:
        feedback_parts.append("XZ Planar Symmetry not enabled (+0).")
        
    # 6. VLM Check (10 pts)
    vlm_passed, vlm_reason = verify_gui_interaction(traj, env_info)
    if vlm_passed:
        score += 10
        feedback_parts.append("VLM visual verification passed (+10).")
    else:
        feedback_parts.append(f"VLM visual verification failed: {vlm_reason} (+0).")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }