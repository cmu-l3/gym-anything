#!/usr/bin/env python3
"""
Verifier for openvsp_airfoil_resection task.

Checks:
1. File exists and differs from original (anti-gaming).
2. WingGeom component present.
3. Root XSec is Four Series (NACA 4-digit).
4. Root parameters match NACA 4415 (Camber=0.04, CamberLoc=0.4, ThickChord=0.15).
5. Tip XSec is Four Series (NACA 4-digit).
6. Tip parameters match NACA 2410 (Camber=0.02, CamberLoc=0.4, ThickChord=0.10).
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET


def verify_openvsp_airfoil_resection(trajectory, env_info, task_info):
    result_file = task_info.get("metadata", {}).get(
        "result_file", "/tmp/openvsp_airfoil_resection_result.json"
    )

    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        env_info["copy_from_env"](result_file, local_tmp)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file not found — export script may not have run: {e}",
        }

    with open(local_tmp, "r") as f:
        data = json.load(f)
    os.unlink(local_tmp)

    score = 0
    feedback_parts = []

    if not data.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "eCRM001_resectioned.vsp3 not found. Agent did not save the file correctly.",
        }
    
    if not data.get("created_during_task", True):
        feedback_parts.append("Warning: File modification time is before task start.")
        
    if not data.get("differs_from_original", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Saved file is identical to the original eCRM-001 model. No modifications were made.",
        }

    content = data.get("file_content", "")
    
    try:
        root = ET.fromstring(content)
        score += 10
        feedback_parts.append("File is valid XML (+10)")
    except ET.ParseError as e:
        return {
            "passed": False,
            "score": 5,
            "feedback": f"File is not valid XML: {e}",
        }

    # Find the Wing component
    wing_geom = None
    for geom in root.findall(".//Geom"):
        geom_type_el = geom.find("Type")
        if geom_type_el is not None and geom_type_el.text == "WingGeom":
            name_el = geom.find(".//Name")
            if name_el is not None and "wing" in name_el.text.lower():
                wing_geom = geom
                break
    
    if wing_geom is None:
        # Fallback to the first WingGeom
        for geom in root.findall(".//Geom"):
            geom_type_el = geom.find("Type")
            if geom_type_el is not None and geom_type_el.text == "WingGeom":
                wing_geom = geom
                break
                
    if wing_geom is None:
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + " | No WingGeom component found in model.",
        }
        
    score += 10
    feedback_parts.append("Wing component found (+10)")

    # Find all XSecCurve elements within this wing
    xsec_curves = wing_geom.findall(".//XSecCurve")
    if not xsec_curves:
        feedback_parts.append("No XSecCurve elements found in Wing.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    root_xsec = xsec_curves[0]
    tip_xsec = xsec_curves[-1]

    def get_curve_type(curve_el):
        type_el = curve_el.find("Type")
        if type_el is not None:
            try:
                return int(type_el.text)
            except ValueError:
                pass
        return -1
        
    def get_param_value(curve_el, param_name):
        param_el = curve_el.find(f".//{param_name}")
        if param_el is not None and "Value" in param_el.attrib:
            try:
                return float(param_el.attrib["Value"])
            except ValueError:
                pass
        return None

    # Check Root XSec (NACA 4415 -> Camber=0.04, Loc=0.4, ThickChord=0.15)
    root_type = get_curve_type(root_xsec)
    if root_type == 7:  # XS_FOUR_SERIES
        score += 10
        feedback_parts.append("Root XSec is Four Series (+10)")
    else:
        feedback_parts.append(f"Root XSec type is {root_type}, not Four Series (7) (+0)")

    root_camber = get_param_value(root_xsec, "Camber")
    root_loc = get_param_value(root_xsec, "CamberLoc")
    root_tc = get_param_value(root_xsec, "ThickChord")

    if root_camber is not None and abs(root_camber - 0.04) <= 0.015:
        score += 10
        feedback_parts.append("Root Camber correct (+10)")
    else:
        val_str = f"{root_camber:.3f}" if root_camber is not None else "None"
        feedback_parts.append(f"Root Camber {val_str} != 0.04 (+0)")

    if root_loc is not None and abs(root_loc - 0.4) <= 0.1:
        score += 5
        feedback_parts.append("Root CamberLoc correct (+5)")
    else:
        val_str = f"{root_loc:.3f}" if root_loc is not None else "None"
        feedback_parts.append(f"Root CamberLoc {val_str} != 0.4 (+0)")

    if root_tc is not None and abs(root_tc - 0.15) <= 0.02:
        score += 15
        feedback_parts.append("Root ThickChord correct (+15)")
    else:
        val_str = f"{root_tc:.3f}" if root_tc is not None else "None"
        feedback_parts.append(f"Root ThickChord {val_str} != 0.15 (+0)")

    # Check Tip XSec (NACA 2410 -> Camber=0.02, Loc=0.4, ThickChord=0.10)
    tip_type = get_curve_type(tip_xsec)
    if tip_type == 7:  # XS_FOUR_SERIES
        score += 10
        feedback_parts.append("Tip XSec is Four Series (+10)")
    else:
        feedback_parts.append(f"Tip XSec type is {tip_type}, not Four Series (7) (+0)")

    tip_camber = get_param_value(tip_xsec, "Camber")
    tip_loc = get_param_value(tip_xsec, "CamberLoc")
    tip_tc = get_param_value(tip_xsec, "ThickChord")

    if tip_camber is not None and abs(tip_camber - 0.02) <= 0.015:
        score += 10
        feedback_parts.append("Tip Camber correct (+10)")
    else:
        val_str = f"{tip_camber:.3f}" if tip_camber is not None else "None"
        feedback_parts.append(f"Tip Camber {val_str} != 0.02 (+0)")

    if tip_loc is not None and abs(tip_loc - 0.4) <= 0.1:
        score += 5
        feedback_parts.append("Tip CamberLoc correct (+5)")
    else:
        val_str = f"{tip_loc:.3f}" if tip_loc is not None else "None"
        feedback_parts.append(f"Tip CamberLoc {val_str} != 0.4 (+0)")

    if tip_tc is not None and abs(tip_tc - 0.10) <= 0.02:
        score += 15
        feedback_parts.append("Tip ThickChord correct (+15)")
    else:
        val_str = f"{tip_tc:.3f}" if tip_tc is not None else "None"
        feedback_parts.append(f"Tip ThickChord {val_str} != 0.10 (+0)")

    passed = score >= 60 and data.get("differs_from_original", False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }