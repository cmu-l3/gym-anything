#!/usr/bin/env python3
"""
Verifier for openvsp_wet_wing_fuel_volume task.

Checks:
  1. eCRM001_wet_wing.vsp3 exists and is valid XML (10 pts)
  2. Subsurface is created with correct spanwise (U) bounds: 0.15 to 0.70 (20 pts)
  3. Subsurface is created with correct chordwise (W) bounds: 0.20 to 0.65 (20 pts)
  4. fuel_capacity_report.txt exists with extracted Volume and calculated Mass (15 pts)
  5. Mathematical validation: Mass exactly equals Volume * 804 (15 pts)
  6. Physical Plausibility: Volume is reasonably bounded > 1.0 m^3 and < 200.0 m^3 (10 pts)
  7. VLM verification: Agent actually opened and used the OpenVSP UI (10 pts)

Pass threshold: 70 points.
"""

import json
import os
import re
import tempfile
import xml.etree.ElementTree as ET

def _find_param_values_by_tag(content: str, tag: str) -> list:
    """Find all Value attributes for elements with the given tag name in OpenVSP XML."""
    pattern = rf'<{tag}\s+Value="([^"]+)"'
    vals = []
    for m in re.finditer(pattern, content):
        try:
            vals.append(float(m.group(1)))
        except ValueError:
            pass
    return vals

def _extract_numeric_value(text: str, keywords: list) -> float:
    """Find a numeric value occurring near specific keywords."""
    patterns = [
        r'(?:' + '|'.join(re.escape(k) for k in keywords) + r')[^\d\-\.]*([+-]?\d+\.?\d*)',
    ]
    for pattern in patterns:
        for m in re.finditer(pattern, text, re.IGNORECASE):
            try:
                return float(m.group(1))
            except ValueError:
                continue
    return None

def verify_openvsp_wet_wing_fuel_volume(trajectory, env_info, task_info):
    result_file = task_info.get("metadata", {}).get(
        "result_file", "/tmp/openvsp_wet_wing_result.json"
    )

    # 1. Copy the JSON result payload from the environment
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    
    # Tolerances
    BOUND_TOLERANCE = 0.03

    # --- Check 1: File Existence & XML Validation (10 pts) ---
    model_exists = data.get("model_exists", False)
    content = data.get("model_content", "").replace("\\n", "\n").replace("\\t", "\t")

    if not model_exists:
        feedback_parts.append("eCRM001_wet_wing.vsp3 not found (+0)")
    else:
        try:
            ET.fromstring(content)
            score += 10
            feedback_parts.append("Model file exists and is valid XML (+10)")
        except ET.ParseError as e:
            feedback_parts.append(f"Model file is not valid XML: {e} (+0)")

    # --- Check 2: Spanwise (U) Bounds (20 pts) ---
    u_starts = _find_param_values_by_tag(content, "U_Start")
    u_ends = _find_param_values_by_tag(content, "U_End")
    
    u_start_ok = any(abs(u - 0.15) <= BOUND_TOLERANCE for u in u_starts)
    u_end_ok = any(abs(u - 0.70) <= BOUND_TOLERANCE for u in u_ends)

    if u_start_ok and u_end_ok:
        score += 20
        feedback_parts.append("Subsurface spanwise (U) bounds correct (+20)")
    elif u_starts or u_ends:
        feedback_parts.append(f"Subsurface U bounds found but incorrect (Starts: {u_starts[:3]}, Ends: {u_ends[:3]}) (+0)")
    else:
        feedback_parts.append("No Subsurface U bounds found (+0)")

    # --- Check 3: Chordwise (W) Bounds (20 pts) ---
    w_starts = _find_param_values_by_tag(content, "W_Start")
    w_ends = _find_param_values_by_tag(content, "W_End")
    
    w_start_ok = any(abs(w - 0.20) <= BOUND_TOLERANCE for w in w_starts)
    w_end_ok = any(abs(w - 0.65) <= BOUND_TOLERANCE for w in w_ends)

    if w_start_ok and w_end_ok:
        score += 20
        feedback_parts.append("Subsurface chordwise (W) bounds correct (+20)")
    elif w_starts or w_ends:
        feedback_parts.append(f"Subsurface W bounds found but incorrect (Starts: {w_starts[:3]}, Ends: {w_ends[:3]}) (+0)")
    else:
        feedback_parts.append("No Subsurface W bounds found (+0)")

    # --- Check 4, 5, 6: Report, Math, and Physical Plausibility ---
    report_exists = data.get("report_exists", False)
    report_content = data.get("report_content", "")

    if not report_exists:
        feedback_parts.append("fuel_capacity_report.txt not found (+0)")
    else:
        score += 5
        feedback_parts.append("Report file exists (+5)")
        
        volume = _extract_numeric_value(report_content, ["Volume", "m^3", "m3"])
        mass = _extract_numeric_value(report_content, ["Mass", "kg", "kilograms"])
        
        if volume is not None and mass is not None:
            score += 10
            feedback_parts.append(f"Extracted values: Volume={volume}, Mass={mass} (+10)")
            
            # Check Math (Mass = Volume * 804)
            expected_mass = volume * 804.0
            if abs(mass - expected_mass) <= (expected_mass * 0.02): # 2% tolerance for rounding
                score += 15
                feedback_parts.append("Mathematical validation passed (Mass ≈ Vol * 804) (+15)")
            else:
                feedback_parts.append(f"Mathematical validation failed (Expected ~{expected_mass:.1f}, got {mass}) (+0)")
                
            # Check Plausibility (Volume > 1.0 and < 200.0)
            if 1.0 < volume < 200.0:
                score += 10
                feedback_parts.append("Volume is physically plausible (+10)")
            else:
                feedback_parts.append("Volume is not physically plausible for eCRM-001 (+0)")
        else:
            feedback_parts.append("Could not extract both Volume and Mass from report (+0)")

    # --- Check 7: VLM Verification for GUI interaction (10 pts) ---
    # Sample trajectory frames to ensure the agent actually opened the GUI 
    # and didn't just python-script the XML blindly.
    query_vlm = env_info.get("query_vlm")
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(trajectory, n=3)
        if frames:
            prompt = (
                "You are an AI verifying a visual task trajectory. "
                "Did the agent interact with the OpenVSP graphical user interface? "
                "Look for the OpenVSP window (a CAD-like interface with a 3D airplane model) "
                "or parameter editing windows. Answer strictly with JSON containing a boolean "
                "'used_gui' flag."
            )
            vlm_result = query_vlm(prompt=prompt, images=frames)
            
            if vlm_result.get("success"):
                try:
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("used_gui", False) or str(parsed).lower().find("true") != -1:
                        score += 10
                        feedback_parts.append("VLM confirmed OpenVSP GUI usage (+10)")
                    else:
                        feedback_parts.append("VLM did not detect GUI usage (+0)")
                except Exception:
                    pass

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }