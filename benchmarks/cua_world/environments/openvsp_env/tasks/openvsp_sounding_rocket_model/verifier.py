#!/usr/bin/env python3
"""
Verifier for openvsp_sounding_rocket_model task.

Checks that the agent created a parametric model matching the sounding rocket specification:
  1. File exists, was created during task, and is valid XML (10 pts)
  2. Axisymmetric body component present (20 pts)
  3. Body has multiple cross-sections (≥3 for nose, cylinder, boat-tail) (15 pts)
  4. Body length approx 2.40 m (15 pts)
  5. Body diameter approx 0.152 m (15 pts)
  6. Fin component(s) present (WingGeom with small span) (15 pts)
  7. Component diversity (≥2 distinct components) (10 pts)

Pass threshold: 55 points (requires body component + some dimensions + fins).
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def get_all_values(elem: ET.Element, tags: list) -> list[float]:
    """Find all 'Value' attributes for given tags within an XML element."""
    vals = []
    for tag in tags:
        for child in elem.iter(tag):
            if 'Value' in child.attrib:
                try:
                    vals.append(float(child.attrib['Value']))
                except ValueError:
                    pass
    return vals


def verify_openvsp_sounding_rocket_model(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get("result_file", "/tmp/openvsp_sounding_rocket_result.json")
    
    # Tolerances defined in task_info metadata
    len_range = metadata.get("target_length_range", [1.68, 3.12])
    dia_range = metadata.get("target_diameter_range", [0.09, 0.22])
    fin_max = metadata.get("fin_max_dimension", 0.60)

    # Copy result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_file, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Check 1: File exists and is valid XML (10 pts) ---
    if not result.get('file_exists', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "sounding_rocket.vsp3 not found. Agent did not save the file.",
        }

    if not result.get('created_during_task', False):
        feedback_parts.append("WARNING: File timestamps suggest it was not modified during the task.")

    if result.get('file_size', 0) < 500:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"File is too small ({result.get('file_size')} bytes) to be a valid model.",
        }

    content = result.get('file_content', '')
    
    try:
        root = ET.fromstring(content)
        score += 10
        feedback_parts.append("Valid OpenVSP XML found (+10).")
    except ET.ParseError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"File is not valid XML: {e}",
        }

    # Extract geometries
    body_types = ["FuselageGeom", "StackGeom", "PodGeom", "BodyOfRevolutionGeom"]
    body_geoms = []
    wing_geoms = []
    
    for geom in root.findall(".//Geom"):
        type_elem = geom.find(".//TypeName")
        if type_elem is not None:
            t_name = type_elem.text
            if t_name in body_types:
                body_geoms.append(geom)
            elif t_name == "WingGeom":
                wing_geoms.append(geom)

    # --- Check 2: Body component present (20 pts) ---
    if body_geoms:
        score += 20
        feedback_parts.append(f"Axisymmetric body component ({len(body_geoms)}) found (+20).")
    else:
        feedback_parts.append("No axisymmetric body component (Fuselage/Stack/Pod) found (+0).")

    # --- Check 3, 4, 5: Body cross-sections, length, and diameter ---
    best_xsec_count = 0
    found_valid_length = False
    found_valid_dia = False
    
    for body in body_geoms:
        # Check cross sections
        xsecs = body.findall(".//XSec")
        if len(xsecs) > best_xsec_count:
            best_xsec_count = len(xsecs)
            
        # Check Length
        lengths = get_all_values(body, ["DesignLength", "Length", "TotalLength"])
        # Some components store length as sections, let's sum them or check if any single value matches
        sum_length = sum(lengths)
        if any(len_range[0] <= l <= len_range[1] for l in lengths) or (len_range[0] <= sum_length <= len_range[1]):
            found_valid_length = True
            
        # Check Diameter/Width/Height
        dias = get_all_values(body, ["DesignWidth", "DesignHeight", "Width", "Height", "Diameter", "Max_Width"])
        if any(dia_range[0] <= d <= dia_range[1] for d in dias):
            found_valid_dia = True

    # Scoring cross-sections (15 pts)
    if best_xsec_count >= 3:
        score += 15
        feedback_parts.append(f"Body has multiple cross-sections (≥3) for nose/tail shaping (+15).")
    elif best_xsec_count > 0:
        score += 5
        feedback_parts.append(f"Body has only {best_xsec_count} cross-sections (need ≥3) (+5).")
    else:
        feedback_parts.append("Body lacks cross-sections (+0).")

    # Scoring length (15 pts)
    if found_valid_length:
        score += 15
        feedback_parts.append(f"Body length is within target range [{len_range[0]}, {len_range[1]}] m (+15).")
    else:
        feedback_parts.append(f"No body length matches target range [{len_range[0]}, {len_range[1]}] m (+0).")

    # Scoring diameter (15 pts)
    if found_valid_dia:
        score += 15
        feedback_parts.append(f"Body diameter is within target range [{dia_range[0]}, {dia_range[1]}] m (+15).")
    else:
        feedback_parts.append(f"No body dimension matches target diameter range [{dia_range[0]}, {dia_range[1]}] m (+0).")

    # --- Check 6: Fin component(s) present (15 pts) ---
    has_valid_fins = False
    if wing_geoms:
        for wing in wing_geoms:
            # Check if dimensions are small enough to be fins (not full aircraft wings)
            spans = get_all_values(wing, ["TotalSpan", "Span", "TotalArea", "Root_Chord"])
            if spans and all(s <= fin_max for s in spans):
                has_valid_fins = True
                break
            # If no parameters could be parsed but a wing exists, give partial credit
            if not spans:
                has_valid_fins = True
                
    if has_valid_fins:
        score += 15
        feedback_parts.append("Fin component(s) (WingGeom with fin-like dimensions) found (+15).")
    elif wing_geoms:
        score += 5
        feedback_parts.append("WingGeom found, but dimensions are too large for sounding rocket fins (+5).")
    else:
        feedback_parts.append("No fin components (WingGeom) found (+0).")

    # --- Check 7: Component diversity (10 pts) ---
    if body_geoms and wing_geoms:
        score += 10
        feedback_parts.append("Model uses multiple distinct component types (body + fins) (+10).")
    else:
        feedback_parts.append("Model lacks component diversity (+0).")

    passed = score >= 55
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }