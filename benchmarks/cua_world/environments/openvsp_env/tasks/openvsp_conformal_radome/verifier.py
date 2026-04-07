#!/usr/bin/env python3
"""
Verifier for openvsp_conformal_radome task.

Verification Strategy:
1. XML Parsing (.vsp3 file):
   - Check if eCRM001_satcom.vsp3 exists and is valid XML. (10 pts)
   - Verify a 'Conformal' geometry component named 'Satcom_Radome' exists. (15 pts)
   - Extract the ID of the 'Fuselage' component and verify 'Satcom_Radome' <ParentID> matches. (25 pts)
   - Verify parametric boundaries inside Satcom_Radome block match spec (U/V/Thick). (30 pts)
2. CompGeom Report:
   - Extract numeric values from radome_report.txt.
   - Check if any value falls within plausible total wetted area range [1100, 1300] m². (20 pts)
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_param_value(radome_elem, possible_tags):
    """Search for a parameter by tag name in the ElementTree and return its float Value."""
    for tag in possible_tags:
        # Search anywhere under the radome element
        for elem in radome_elem.iter():
            if elem.tag.lower() == tag.lower() and "Value" in elem.attrib:
                try:
                    return float(elem.attrib["Value"])
                except ValueError:
                    pass
    return None

def extract_wetted_area(text):
    """Find a plausible wetted area number in the report text."""
    # Find all decimal/integer numbers
    numbers = re.findall(r'[+-]?\d+\.?\d*', text)
    for n in numbers:
        try:
            val = float(n)
            # Baseline eCRM is ~1141 m^2. Plausible range is 1100 to 1300 m^2.
            if 1100.0 <= val <= 1300.0:
                return val
        except ValueError:
            pass
    return None

def verify_openvsp_conformal_radome(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    expected_u_min = metadata.get("expected_u_min", 0.25)
    expected_u_max = metadata.get("expected_u_max", 0.30)
    expected_v_min = metadata.get("expected_v_min", 0.45)
    expected_v_max = metadata.get("expected_v_max", 0.55)
    expected_thick = metadata.get("expected_thick", 0.35)

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    task_start = result.get("task_start_time", 0)
    model = result.get("model", {})
    report = result.get("report", {})

    # --- 1. Check Model Existence and XML (10 pts) ---
    if not model.get("exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Model file /home/ga/Documents/OpenVSP/eCRM001_satcom.vsp3 not found."
        }
    
    if model.get("mtime", 0) < task_start:
        feedback_parts.append("WARNING: Model file was modified before task start (Anti-Gaming).")

    try:
        root = ET.fromstring(model.get("content", ""))
        score += 10
        feedback_parts.append("Model file is valid XML.")
    except ET.ParseError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Model file exists but is not valid XML: {e}"
        }

    # --- 2. Find Fuselage and Satcom_Radome Components (15 pts) ---
    fuselage_id = None
    radome_geom = None

    for geom in root.findall(".//Geom"):
        name_elem = geom.find("Name")
        type_elem = geom.find("Type")
        if name_elem is not None:
            # Check for Fuselage
            if name_elem.text == "Fuselage":
                id_elem = geom.find("ID")
                if id_elem is not None:
                    fuselage_id = id_elem.text
            
            # Check for Radome
            if name_elem.text == "Satcom_Radome":
                if type_elem is not None and type_elem.text == "Conformal":
                    radome_geom = geom
                else:
                    feedback_parts.append("Found Satcom_Radome but Type is not Conformal.")

    if radome_geom is not None:
        score += 15
        feedback_parts.append("Conformal Satcom_Radome component found.")
    else:
        feedback_parts.append("Satcom_Radome (Conformal) component not found.")
        # Cannot check topology or params if it doesn't exist
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # --- 3. Check Parent-Child Topology (25 pts) ---
    parent_elem = radome_geom.find("ParentID")
    if parent_elem is not None and fuselage_id is not None:
        if parent_elem.text == fuselage_id:
            score += 25
            feedback_parts.append("Topological link (Parent=Fuselage) is correct.")
        else:
            feedback_parts.append("Satcom_Radome ParentID does not match Fuselage ID.")
    else:
        feedback_parts.append("Could not verify ParentID link to Fuselage.")

    # --- 4. Check Parametric Bounds (30 pts) ---
    # Give 6 points for each correct parameter
    u_min = get_param_value(radome_geom, ["U_Min", "UMin"])
    u_max = get_param_value(radome_geom, ["U_Max", "UMax"])
    v_min = get_param_value(radome_geom, ["V_Min", "VMin"])
    v_max = get_param_value(radome_geom, ["V_Max", "VMax"])
    thick = get_param_value(radome_geom, ["Thick", "Thickness"])

    params_correct = 0
    tol = 0.01

    if u_min is not None and abs(u_min - expected_u_min) <= tol: params_correct += 1
    if u_max is not None and abs(u_max - expected_u_max) <= tol: params_correct += 1
    if v_min is not None and abs(v_min - expected_v_min) <= tol: params_correct += 1
    if v_max is not None and abs(v_max - expected_v_max) <= tol: params_correct += 1
    if thick is not None and abs(thick - expected_thick) <= tol: params_correct += 1

    score += (params_correct * 6)
    feedback_parts.append(f"{params_correct}/5 parametric bounds correct.")

    # --- 5. Check CompGeom Report (20 pts) ---
    if not report.get("exists", False):
        feedback_parts.append("radome_report.txt not found.")
    else:
        report_content = report.get("content", "")
        wetted_area = extract_wetted_area(report_content)
        if wetted_area is not None:
            score += 20
            feedback_parts.append(f"Plausible total wetted area found in report: {wetted_area:.1f} m².")
        else:
            feedback_parts.append("No plausible wetted area [1100-1300] found in report.")

    # Final Evaluation
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }