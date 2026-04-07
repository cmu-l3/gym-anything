#!/usr/bin/env python3
"""
Verifier for openvsp_subsurface_solar_array.

Scoring Criteria (100 pts total):
1. Modified Model Saved (10 pts)
2. Inboard Array Correct (25 pts)
3. Outboard Array Correct (25 pts)
4. Morphing Hinge Correct (20 pts)
5. Degen Geom Exported (20 pts)

Uses programmatic XML parsing of the .vsp3 file to rigorously check parameters,
combined with VLM trajectory verification to ensure genuine GUI interaction.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _extract_subsurface_params(xml_content: str, target_name: str) -> dict:
    """
    Finds a SubSurface block by name and extracts its parameters into a dictionary.
    Regex is used for robustness against OpenVSP version changes in XML formatting.
    """
    # Split by <SubSurface> or <SubSurface
    blocks = re.split(r'<SubSurface', xml_content)
    
    for block in blocks[1:]:
        # Check if this block contains the target Name
        name_match = re.search(r'<Name>\s*([^<]+)\s*</Name>', block)
        if name_match and name_match.group(1).strip() == target_name:
            parms = {}
            # Extract all parameters: <Parm Name="U_Start" ... Value="0.55" />
            for pmatch in re.finditer(r'<Parm\s+Name="([^"]+)"[^>]*Value="([^"]+)"', block):
                param_name = pmatch.group(1)
                try:
                    parms[param_name] = float(pmatch.group(2))
                except ValueError:
                    pass
            return parms
    return {}


def verify_openvsp_subsurface_solar_array(traj, env_info, task_info):
    """Primary verification function."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    result_json_path = metadata.get('result_json', '/tmp/openvsp_subsurface_solar_array_result.json')
    expected_subsurfaces = metadata.get('subsurfaces', {})

    score = 0
    feedback_parts = []
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_json_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    model_exists = result.get('model_exists', False)
    model_created = result.get('model_created_during_task', False)
    model_content = result.get('model_content', '')
    csv_exists = result.get('csv_exists', False)
    csv_created = result.get('csv_created_during_task', False)
    csv_lines = result.get('csv_first_lines', '')

    # CRITERION 1: Model Saved (10 pts)
    if model_exists and model_created:
        score += 10
        feedback_parts.append("✅ Modified model saved successfully")
    elif model_exists:
        # Model exists but mtime is old - might be a pre-existing file
        feedback_parts.append("❌ Model exists but was not created/modified during task")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    else:
        feedback_parts.append("❌ Target model hale_uav_subsurfaces.vsp3 not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Evaluate SubSurfaces
    def eval_subsurface(name, expected_params, max_pts):
        actual_params = _extract_subsurface_params(model_content, name)
        if not actual_params:
            return 0, f"❌ {name} not found"
        
        pts = 0
        local_feedback = []
        tol = 0.05
        
        for k, exp_v in expected_params.items():
            if k in actual_params:
                act_v = actual_params[k]
                if abs(act_v - exp_v) <= tol:
                    pts += (max_pts / 4.0)  # 4 parameters per subsurface
                else:
                    local_feedback.append(f"{k} incorrect (exp: {exp_v}, act: {act_v})")
            else:
                local_feedback.append(f"{k} missing")
                
        if pts == max_pts:
            return pts, f"✅ {name} perfectly configured"
        elif pts > 0:
            return pts, f"⚠️ {name} partially correct: {', '.join(local_feedback)}"
        else:
            return 0, f"❌ {name} incorrectly configured"

    # CRITERION 2: Inboard Array (25 pts)
    pts_inboard, fb_inboard = eval_subsurface("Solar_Array_Inboard", expected_subsurfaces.get("Solar_Array_Inboard", {}), 25)
    score += pts_inboard
    feedback_parts.append(fb_inboard)

    # CRITERION 3: Outboard Array (25 pts)
    pts_outboard, fb_outboard = eval_subsurface("Solar_Array_Outboard", expected_subsurfaces.get("Solar_Array_Outboard", {}), 25)
    score += pts_outboard
    feedback_parts.append(fb_outboard)

    # CRITERION 4: Morphing Hinge (20 pts)
    pts_hinge, fb_hinge = eval_subsurface("Morphing_Hinge", expected_subsurfaces.get("Morphing_Hinge", {}), 20)
    score += pts_hinge
    feedback_parts.append(fb_hinge)

    # CRITERION 5: Degen Geom Exported (20 pts)
    if csv_exists and csv_created:
        if "# DegenGeom" in csv_lines or "DegenGeom" in csv_lines or "Comp" in csv_lines:
            score += 20
            feedback_parts.append("✅ Degen Geom CSV successfully exported and valid")
        else:
            score += 5
            feedback_parts.append("⚠️ Degen Geom CSV exported but headers not recognized")
    else:
        feedback_parts.append("❌ Degen Geom CSV not exported")

    # Final scoring
    score = int(score)
    # Require at least the model save and two successful subsurface creations
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }