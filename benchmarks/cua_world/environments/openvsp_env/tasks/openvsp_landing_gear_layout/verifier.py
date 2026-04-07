#!/usr/bin/env python3
"""
Verifier for openvsp_landing_gear_layout task.

Scoring (100 pts total):
1. Math: Report contains correct X_main (36.07 ± 0.15) — 15 pts
2. Math: Report contains correct X_nose (0.35 ± 0.15) — 15 pts
3. GUI: Model saved and valid XML — 10 pts
4. GUI: 'MainGear' component created and positioned correctly — 25 pts
5. GUI: 'MainGear' has Y-Symmetry enabled — 10 pts
6. GUI: 'NoseGear' component created and positioned correctly — 25 pts

Pass threshold: 70 points
"""

import json
import os
import re
import tempfile
import xml.etree.ElementTree as ET

def _find_number_near_keyword(text: str, keywords: list) -> float | None:
    text_lower = text.lower()
    for kw in keywords:
        idx = text_lower.find(kw.lower())
        if idx >= 0:
            window = text[max(0, idx - 15): idx + 40]
            nums = re.findall(r'[+-]?\d+\.?\d*', window)
            if nums:
                try:
                    return float(nums[0])
                except ValueError:
                    continue
    return None

def _get_geom_by_name(root, name: str):
    """Find a <Geom> element with the exact <Name>."""
    for geom in root.iter('Geom'):
        name_elem = geom.find('Name')
        if name_elem is not None and name_elem.text == name:
            return geom
    return None

def _get_param_value(geom, param_name: str) -> float | None:
    """Find an OpenVSP parameter by its tag and get its Value attribute."""
    for elem in geom.iter(param_name):
        val = elem.attrib.get('Value')
        if val is not None:
            return float(val)
    return None

def _has_symmetry(geom) -> bool:
    """Check if symmetry is enabled (Sym_Planar_Flag or Sym_Y >= 1)."""
    for sym_tag in ['Sym_Planar_Flag', 'Sym_Y', 'Sym_Planar']:
        val = _get_param_value(geom, sym_tag)
        if val is not None and val >= 1.0:
            return True
    return False

def verify_openvsp_landing_gear_layout(trajectory, env_info, task_info):
    result_file = task_info.get("metadata", {}).get(
        "result_file", "/tmp/openvsp_landing_gear_layout_result.json"
    )
    expected_x_main = task_info.get("metadata", {}).get("expected_x_main", 36.07)
    expected_x_nose = task_info.get("metadata", {}).get("expected_x_nose", 0.35)
    tol = task_info.get("metadata", {}).get("tolerance_m", 0.15)

    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        env_info["copy_from_env"](result_file, local_tmp)
        with open(local_tmp, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(local_tmp):
            os.unlink(local_tmp)

    score = 0
    feedback_parts = []

    # --- Math Check (30 pts) ---
    report_content = data.get("report_content", "")
    if not data.get("report_exists", False):
        feedback_parts.append("Report file gear_report.txt not found (+0)")
    else:
        # Check X_main
        rep_x_main = _find_number_near_keyword(report_content, ["main", "x_main"])
        if rep_x_main is not None and abs(rep_x_main - expected_x_main) <= tol:
            score += 15
            feedback_parts.append(f"Math: X_main correct ({rep_x_main:.2f}) (+15)")
        else:
            feedback_parts.append(f"Math: X_main missing or incorrect (found {rep_x_main}) (+0)")

        # Check X_nose
        rep_x_nose = _find_number_near_keyword(report_content, ["nose", "x_nose"])
        if rep_x_nose is not None and abs(rep_x_nose - expected_x_nose) <= tol:
            score += 15
            feedback_parts.append(f"Math: X_nose correct ({rep_x_nose:.2f}) (+15)")
        else:
            feedback_parts.append(f"Math: X_nose missing or incorrect (found {rep_x_nose}) (+0)")

    # --- GUI / XML Check (70 pts) ---
    if not data.get("model_exists", False):
        feedback_parts.append("Model eCRM001_geared.vsp3 not saved (+0)")
    else:
        # Anti-gaming: Ensure file was modified during task
        if data.get("model_mtime", 0) < data.get("task_start", 0):
            feedback_parts.append("Model file predates task start (Anti-gaming triggered) (+0)")
        else:
            try:
                root = ET.fromstring(data.get("model_content", ""))
                score += 10
                feedback_parts.append("File saved and valid XML (+10)")

                # Verify MainGear
                main_geom = _get_geom_by_name(root, "MainGear")
                if main_geom is None:
                    feedback_parts.append("Component 'MainGear' not found (+0)")
                else:
                    x_loc = _get_param_value(main_geom, "X_Location")
                    y_loc = _get_param_value(main_geom, "Y_Location")
                    z_loc = _get_param_value(main_geom, "Z_Location")

                    if x_loc is not None and abs(x_loc - expected_x_main) <= tol and \
                       y_loc is not None and abs(y_loc - 4.0) <= 0.1 and \
                       z_loc is not None and abs(z_loc - -3.0) <= 0.1:
                        score += 25
                        feedback_parts.append(f"MainGear placement correct (X={x_loc:.2f}, Y={y_loc:.1f}, Z={z_loc:.1f}) (+25)")
                    else:
                        feedback_parts.append(f"MainGear placement incorrect (X={x_loc}, Y={y_loc}, Z={z_loc}) (+0)")

                    if _has_symmetry(main_geom):
                        score += 10
                        feedback_parts.append("MainGear Y-Symmetry is ON (+10)")
                    else:
                        feedback_parts.append("MainGear Y-Symmetry is OFF (+0)")

                # Verify NoseGear
                nose_geom = _get_geom_by_name(root, "NoseGear")
                if nose_geom is None:
                    feedback_parts.append("Component 'NoseGear' not found (+0)")
                else:
                    x_loc = _get_param_value(nose_geom, "X_Location")
                    y_loc = _get_param_value(nose_geom, "Y_Location")
                    z_loc = _get_param_value(nose_geom, "Z_Location")

                    if x_loc is not None and abs(x_loc - expected_x_nose) <= tol and \
                       z_loc is not None and abs(z_loc - -3.0) <= 0.1:
                        score += 25
                        feedback_parts.append(f"NoseGear placement correct (X={x_loc:.2f}, Z={z_loc:.1f}) (+25)")
                    else:
                        feedback_parts.append(f"NoseGear placement incorrect (X={x_loc}, Z={z_loc}) (+0)")

            except ET.ParseError:
                feedback_parts.append("Model file is not valid XML (+0)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }