#!/usr/bin/env python3
"""
Verifier for openvsp_ekranoplan_wig_concept task.

Checks:
  1. wig_concept.vsp3 exists and was saved during the task (15 pts)
  2. File is valid XML containing at least 1 Fuselage and 3 Wings (15 pts)
  3. Wing Endplate: At least one WingSect has a Dihedral parameter around -90° (20 pts)
  4. T-Tail: At least one Wing component has a Z_Location or Z_Rel_Location >= 3.5 (20 pts)
  5. Asymmetric Tail: At least one Wing component has Sym_Planar_Flag = 0 (10 pts)
  6. VLM trajectory verification shows visual evidence of the aircraft configuration (20 pts)
"""

import json
import os
import re
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants
ENDPLATE_DIHEDRAL_RANGE = (-100.0, -80.0)
T_TAIL_MIN_Z = 3.5


def _get_values_by_tag(xml_string: str, tag_name: str) -> list:
    """Extract numeric values from XML tags like <TagName Value="1.23".../>"""
    pattern = rf'<{tag_name}\s+Value="([^"]+)"'
    matches = re.findall(pattern, xml_string)
    vals = []
    for m in matches:
        try:
            vals.append(float(m))
        except ValueError:
            pass
    return vals


def verify_wig_concept(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    result_file = task_info.get("metadata", {}).get("result_file", "/tmp/task_result.json")
    
    # Retrieve result JSON from container
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

    # 1. Check file existence and anti-gaming (15 pts)
    file_exists = data.get("file_exists", False)
    created_during_task = data.get("created_during_task", False)
    
    if not file_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "wig_concept.vsp3 not found. Agent did not save the correct file."
        }
        
    if not created_during_task:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "File existed before task and was not modified. Possible gaming."
        }
    
    score += 15
    feedback_parts.append("File correctly saved during task (+15)")

    # 2. Check XML structure and Components (15 pts)
    content = data.get("file_content", "")
    try:
        ET.fromstring(content)
        # Count geoms
        num_fuselages = content.count("<FuselageGeom>") + content.count("<PodGeom>")
        num_wings = content.count("<WingGeom>")
        
        if num_fuselages >= 1 and num_wings >= 3:
            score += 15
            feedback_parts.append(f"Found {num_fuselages} Fuselage(s) and {num_wings} Wing(s) (+15)")
        else:
            feedback_parts.append(f"Missing components: Found {num_fuselages} Fuselages, {num_wings} Wings (Expected 1+ Fuselage, 3+ Wings)")
    except ET.ParseError:
        feedback_parts.append("File is not valid XML")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 3. Check Endplate Dihedral (20 pts)
    dihedrals = _get_values_by_tag(content, "Dihedral")
    has_endplate = any(ENDPLATE_DIHEDRAL_RANGE[0] <= d <= ENDPLATE_DIHEDRAL_RANGE[1] for d in dihedrals)
    if has_endplate:
        score += 20
        feedback_parts.append("Found -90° dihedral endplate (+20)")
    else:
        feedback_parts.append("No downward wing endplate (-90° dihedral) found")

    # 4. Check T-Tail Z Location (20 pts)
    z_locs = _get_values_by_tag(content, "Z_Location") + _get_values_by_tag(content, "Z_Rel_Location")
    has_ttail = any(z >= T_TAIL_MIN_Z for z in z_locs)
    if has_ttail:
        score += 20
        feedback_parts.append(f"Found T-Tail elevated component (Z >= {T_TAIL_MIN_Z}) (+20)")
    else:
        feedback_parts.append("No elevated horizontal tail found for T-Tail config")

    # 5. Check Asymmetric Tail (10 pts)
    sym_flags = _get_values_by_tag(content, "Sym_Planar_Flag")
    has_asymmetric = any(int(s) == 0 for s in sym_flags)
    if has_asymmetric:
        score += 10
        feedback_parts.append("Found asymmetric tail component (+10)")
    else:
        feedback_parts.append("No component with disabled symmetry found")

    # 6. VLM Trajectory Verification (20 pts)
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=3)
            final_img = get_final_screenshot(traj)
            images = [f for f in frames if f]
            if final_img:
                images.append(final_img)

            vlm_prompt = """You are verifying an aerospace design task in OpenVSP.
            The user was tasked with creating a Wing-In-Ground (WIG) effect vehicle with:
            1. A central fuselage
            2. A main wing featuring DOWNWARD-pointing wingtips (endplates)
            3. A T-Tail (a horizontal tail mounted high on top of a vertical tail)
            
            Based on these screenshots of their session and the final model, did they visually accomplish this?
            
            Respond with JSON:
            {
                "has_downward_wingtips": true/false,
                "has_ttail": true/false,
                "confidence": "high/medium/low",
                "reasoning": "brief explanation"
            }
            """
            vlm_result = query_vlm(prompt=vlm_prompt, images=images)
            
            if vlm_result.get("success") and "parsed" in vlm_result:
                parsed = vlm_result["parsed"]
                vlm_score = 0
                if parsed.get("has_downward_wingtips"): vlm_score += 10
                if parsed.get("has_ttail"): vlm_score += 10
                
                score += vlm_score
                feedback_parts.append(f"VLM Visual check awarded {vlm_score}/20 pts: {parsed.get('reasoning', 'No reasoning provided')}")
            else:
                feedback_parts.append("VLM verification failed to parse")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            feedback_parts.append("VLM verification skipped due to error")
    else:
        feedback_parts.append("VLM functionality not available")

    # Final pass logic: Requires file + majority of XML parameter checks
    passed = score >= 70 and has_endplate and has_ttail

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }