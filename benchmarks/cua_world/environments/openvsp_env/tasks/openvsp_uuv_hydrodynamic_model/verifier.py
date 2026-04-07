#!/usr/bin/env python3
"""
Verifier for openvsp_uuv_hydrodynamic_model task.

Checks that the agent built an OpenVSP model with:
  1. File existence of both output files (10 pts)
  2. Hull Geometry: Axisymmetric component with L~3.5m, D~0.35m (20 pts)
  3. Fin Geometry: Wing component present (10 pts)
  4. Propeller Geometry: Propeller component with D~0.25m, Aft positioned (10 pts)
  5. CompGeom Output: Report Volume in [0.20, 0.32] (15 pts)
  6. CompGeom Output: Report Wetted Area in [2.5, 4.0] (10 pts)
  7. VLM Trajectory Verification: Confirms visual workflow of UUV and CompGeom (25 pts)

Pass threshold: 70 points AND key criteria met.
"""

import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt
VLM_PROMPT = """You are verifying if an agent successfully completed a UUV (submarine) design task in OpenVSP.

Look at these trajectory screenshots and the final state.
Determine:
1. Is the OpenVSP application open and being used?
2. Is there a 3D model of an underwater vehicle/submarine visible (should have a cylindrical hull, tail fins, and an aft propeller)?
3. Did the agent open the 'CompGeom' (Computational Geometry) tool window or display analysis results at any point?

Respond in JSON format exactly like this:
{
    "openvsp_used": true/false,
    "uuv_model_visible": true/false,
    "compgeom_tool_visible": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}
"""

def _extract_number(text: str, keywords: list) -> float:
    """Find a number near any of the keywords in text."""
    patterns = [
        r'(?:' + '|'.join(re.escape(k) for k in keywords) + r')[^\d\-\.]*([+-]?\d+\.?\d*)',
        r'([+-]?\d+\.?\d*)[^\d]*(?:' + '|'.join(re.escape(k) for k in keywords) + r')',
    ]
    for pattern in patterns:
        for m in re.finditer(pattern, text, re.IGNORECASE):
            try:
                return float(m.group(1))
            except (ValueError, IndexError):
                continue
    return None

def verify_openvsp_uuv_hydrodynamic_model(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", "/tmp/openvsp_uuv_hydro_result.json")
    
    vol_range = metadata.get("target_volume_range", [0.20, 0.32])
    area_range = metadata.get("target_wetted_area_range", [2.5, 4.0])

    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env(result_file, local_tmp)
        with open(local_tmp, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file not found — export script may not have run: {e}"
        }
    finally:
        if os.path.exists(local_tmp):
            os.unlink(local_tmp)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Check File Existence & Creation (10 pts)
    # ---------------------------------------------------------
    vsp_exists = data.get("vsp_exists", False)
    vsp_created = data.get("vsp_created_during_task", False)
    report_exists = data.get("report_exists", False)
    report_created = data.get("report_created_during_task", False)
    
    if vsp_exists and report_exists:
        if vsp_created and report_created:
            score += 10
            feedback_parts.append("Both deliverables created during task (+10)")
        else:
            score += 5
            feedback_parts.append("Deliverables exist but may not be newly created (+5)")
    else:
        feedback_parts.append("Missing one or more required deliverables (+0)")

    # ---------------------------------------------------------
    # XML Parsing Setup
    # ---------------------------------------------------------
    content = data.get("vsp_content", "").replace("\\n", "\n")
    components = content.split("<Component>")
    
    hull_found = False
    hull_correct = False
    wing_found = False
    prop_found = False
    prop_correct = False

    # ---------------------------------------------------------
    # 2, 3, 4. Component Geometry Checks (20 + 10 + 10 = 40 pts)
    # ---------------------------------------------------------
    for comp in components:
        # Check Hull (Fuselage/Pod/BodyOfRevolution)
        if any(t in comp for t in ["<Type>Fuselage</Type>", "<Type>Pod</Type>", "<Type>Stack</Type>", "<Type>BodyOfRevolution</Type>"]):
            hull_found = True
            lengths = re.findall(r'<Length\s+Value="([^"]+)"', comp) + re.findall(r'<Design_Length\s+Value="([^"]+)"', comp)
            widths = re.findall(r'<Design_Width\s+Value="([^"]+)"', comp) + re.findall(r'<Diameter\s+Value="([^"]+)"', comp)
            
            l_ok = False
            w_ok = False
            for l in lengths:
                if 3.3 <= float(l) <= 3.7:
                    l_ok = True
            for w in widths:
                if 0.32 <= float(w) <= 0.38:
                    w_ok = True
                    
            if l_ok and w_ok:
                hull_correct = True
                
        # Check Fins
        if "<Type>Wing</Type>" in comp:
            wing_found = True
            
        # Check Propeller
        if "<Type>Propeller</Type>" in comp:
            prop_found = True
            dias = re.findall(r'<Diameter\s+Value="([^"]+)"', comp)
            x_locs = re.findall(r'<X_Rel_Location\s+Value="([^"]+)"', comp) + re.findall(r'<X_Location\s+Value="([^"]+)"', comp)
            
            d_ok = any(0.20 <= float(d) <= 0.30 for d in dias)
            # Propeller should be positioned aft (> 3.0m)
            x_ok = any(float(x) > 3.0 for x in x_locs)
            
            if d_ok and x_ok:
                prop_correct = True

    if hull_correct:
        score += 20
        feedback_parts.append("Valid Hull geometry found (+20)")
    elif hull_found:
        score += 10
        feedback_parts.append("Hull found but dimensions incorrect (+10)")
    else:
        feedback_parts.append("No suitable Hull component found (+0)")

    if wing_found:
        score += 10
        feedback_parts.append("Fin/Wing component found (+10)")
    else:
        feedback_parts.append("No Fin/Wing component found (+0)")
        
    if prop_correct:
        score += 10
        feedback_parts.append("Propeller correctly sized and positioned (+10)")
    elif prop_found:
        score += 5
        feedback_parts.append("Propeller found but size/position incorrect (+5)")
    else:
        feedback_parts.append("No Propeller found (+0)")

    # ---------------------------------------------------------
    # 5 & 6. CompGeom Report Checks (15 + 10 = 25 pts)
    # ---------------------------------------------------------
    report = data.get("report_content", "")
    vol_val = _extract_number(report, ["volume", "theoretical volume", "displacement"])
    area_val = _extract_number(report, ["wetted area", "wetted", "area"])

    vol_ok = False
    if vol_val is not None:
        if vol_range[0] <= vol_val <= vol_range[1]:
            score += 15
            vol_ok = True
            feedback_parts.append(f"Valid Volume reported: {vol_val} m3 (+15)")
        else:
            feedback_parts.append(f"Volume {vol_val} is outside valid range {vol_range} (+0)")
    else:
        feedback_parts.append("No Volume found in report (+0)")

    if area_val is not None:
        if area_range[0] <= area_val <= area_range[1]:
            score += 10
            feedback_parts.append(f"Valid Wetted Area reported: {area_val} m2 (+10)")
        else:
            feedback_parts.append(f"Wetted Area {area_val} is outside valid range {area_range} (+0)")
    else:
        feedback_parts.append("No Wetted Area found in report (+0)")

    # ---------------------------------------------------------
    # 7. VLM Trajectory Verification (25 pts)
    # ---------------------------------------------------------
    vlm_ok = False
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        vlm_res = query_vlm(images=frames, prompt=VLM_PROMPT)
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            openvsp_used = parsed.get("openvsp_used", False)
            model_vis = parsed.get("uuv_model_visible", False)
            compgeom_vis = parsed.get("compgeom_tool_visible", False)
            
            vlm_score = 0
            if openvsp_used: vlm_score += 5
            if model_vis: vlm_score += 10
            if compgeom_vis: vlm_score += 10
            
            score += vlm_score
            vlm_ok = (vlm_score == 25)
            feedback_parts.append(f"VLM Visual check: {vlm_score}/25 pts")
        else:
            feedback_parts.append("VLM Verification failed or skipped (+0)")
    else:
        feedback_parts.append("VLM API unavailable (+0)")

    # Determine Pass/Fail
    # Must meet a minimum score threshold and have both a correct hull structure and volume recorded
    key_criteria_met = hull_correct and vol_ok and vsp_created
    passed = (score >= 70) and key_criteria_met

    if passed:
        feedback_parts.insert(0, "SUCCESS: All key hydrodynamic criteria met.")
    else:
        feedback_parts.insert(0, "FAILED: Key criteria or threshold not met.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }