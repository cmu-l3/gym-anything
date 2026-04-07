#!/usr/bin/env python3
"""
Verifier for openvsp_joined_wing_config task.

Evaluates:
  1. Output file exists and was modified during task (10 pts)
  2. Aft_Wing WingGeom component exists (15 pts)
  3. X/Z positioning is correct (15 pts)
  4. Negative sweep (-28 deg) is applied (20 pts)
  5. Negative dihedral (-12 deg) is applied (20 pts)
  6. Global Reference Area updated to 54.0 m^2 (20 pts)

Uses VLM trajectory analysis to verify UI interaction.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _extract_param_value(xml_block: str, tag_name: str) -> list[float]:
    """Find all Value attributes for elements with the given tag name in an XML block."""
    pattern = rf'<{tag_name}\s+Value="([^"]+)"'
    vals = []
    for m in re.finditer(pattern, xml_block):
        try:
            vals.append(float(m.group(1)))
        except ValueError:
            pass
    return vals


def verify_openvsp_joined_wing_config(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_ref_area = metadata.get('expected_ref_area', 54.0)
    expected_sweep = metadata.get('expected_sweep', -28.0)
    expected_dihedral = metadata.get('expected_dihedral', -12.0)
    expected_x = metadata.get('expected_x', 14.0)
    expected_z = metadata.get('expected_z', 2.5)

    result_file = "/tmp/openvsp_joined_wing_config_result.json"
    local_tmp = tempfile.mktemp(suffix=".json")

    try:
        copy_from_env(result_file, local_tmp)
        with open(local_tmp, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(local_tmp):
            os.unlink(local_tmp)

    score = 0
    feedback_parts = []

    # --- 1. Basic File Checks (10 points) ---
    if not data.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "box_wing_complete.vsp3 not found. Agent may not have saved the file."
        }

    if data.get("file_created_during_task", False):
        score += 10
        feedback_parts.append("File created/modified during task (+10)")
    else:
        feedback_parts.append("Warning: File timestamp indicates it was not modified during task.")

    content = data.get("file_content", "")

    # --- 2. Component Creation Check (15 points) ---
    geoms = content.split("<Geom>")
    aft_wing_block = None
    
    for g in geoms:
        if "Aft" in g and "<Type>Wing</Type>" in g:
            aft_wing_block = g
            break

    if aft_wing_block:
        score += 15
        feedback_parts.append("Aft_Wing component found (+15)")
    else:
        feedback_parts.append("Aft_Wing WingGeom component not found (+0)")

    # --- Analyze Aft_Wing geometry if found ---
    if aft_wing_block:
        # 3. Position Check (15 points)
        x_locs = _extract_param_value(aft_wing_block, "X_Rel_Location")
        z_locs = _extract_param_value(aft_wing_block, "Z_Rel_Location")
        
        x_correct = any(abs(x - expected_x) <= 0.5 for x in x_locs)
        z_correct = any(abs(z - expected_z) <= 0.5 for z in z_locs)
        
        if x_correct and z_correct:
            score += 15
            feedback_parts.append(f"Aft_Wing positioned correctly near X={expected_x}, Z={expected_z} (+15)")
        elif x_correct or z_correct:
            score += 7
            feedback_parts.append("Aft_Wing partially positioned correctly (+7)")
        else:
            feedback_parts.append(f"Aft_Wing position incorrect (found X:{x_locs}, Z:{z_locs}) (+0)")

        # 4. Sweep Check (20 points)
        sweeps = _extract_param_value(aft_wing_block, "Sweep")
        if any(abs(s - expected_sweep) <= 4.0 for s in sweeps):
            score += 20
            feedback_parts.append(f"Negative sweep ~{expected_sweep} applied (+20)")
        else:
            feedback_parts.append(f"Correct negative sweep not applied (found: {sweeps}) (+0)")

        # 5. Dihedral Check (20 points)
        dihedrals = _extract_param_value(aft_wing_block, "Dihedral")
        if any(abs(d - expected_dihedral) <= 3.0 for d in dihedrals):
            score += 20
            feedback_parts.append(f"Negative dihedral ~{expected_dihedral} applied (+20)")
        else:
            feedback_parts.append(f"Correct negative dihedral not applied (found: {dihedrals}) (+0)")

    # --- 6. Global Reference Area Check (20 points) ---
    ref_block = content.split("<Reference>")[1].split("</Reference>")[0] if "<Reference>" in content else ""
    areas = _extract_param_value(ref_block, "Area")
    
    if any(abs(a - expected_ref_area) <= 1.0 for a in areas):
        score += 20
        feedback_parts.append(f"Global Reference Area set correctly to ~{expected_ref_area} (+20)")
    else:
        feedback_parts.append(f"Global Reference Area not updated correctly (found: {areas}) (+0)")

    # --- VLM Verification (Anti-Gaming) ---
    # We use VLM to ensure the agent actually interacted with the UI to do the task.
    # OpenVSP XMLs are easy to generate via python scripting, we want to evaluate UI driving.
    query_vlm = env_info.get("query_vlm")
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        vlm_prompt = (
            "Did the user use the OpenVSP GUI in this session? "
            "Look for evidence of adding a wing component ('Aft_Wing') or opening the Model -> Reference window. "
            "Respond in JSON format: {'used_gui': true/false, 'reasoning': '...'}"
        )
        
        try:
            vlm_res = query_vlm(prompt=vlm_prompt, images=frames)
            used_gui = vlm_res.get("parsed", {}).get("used_gui", False)
            if used_gui:
                feedback_parts.append("VLM verified GUI interaction")
            else:
                score = max(0, score - 30)
                feedback_parts.append("Penalty: VLM did not detect sufficient GUI interaction (-30)")
        except Exception as e:
            logger.error(f"VLM check failed: {e}")

    # Determine passing (Requires saving the file and getting at least Reference Area or Geometry correct)
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }