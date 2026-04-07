#!/usr/bin/env python3
"""
Verifier for openvsp_evtol_lift_boom_integration task.

Checks:
  1. Target file `ecrm_evtol.vsp3` exists and is valid XML.
  2. Original eCRM components (Fuselage, Wing) are preserved (Anti-gaming).
  3. A component named "Boom" exists.
  4. Boom Length is ~14.0m.
  5. Boom Diameter/Width is ~1.0m.
  6. Spanwise Placement (Y) is ~8.5m.
  7. Fore/Aft Placement (X) is ~12.0m.
  8. Vertical Placement (Z) is ~0.8m.
  9. XZ Symmetry flag is enabled for the Boom.

Total: 100 points. Pass threshold: 70 points.
"""

import json
import os
import re
import tempfile
import xml.etree.ElementTree as ET


def _get_values(xml_str: str, param_name: str) -> list[float]:
    """
    Robustly extract parameter values from an OpenVSP XML component chunk.
    Searches for <TagName Value="X"> where TagName relates to param_name.
    """
    vals = []
    
    # Pattern 1: Exact tag match <X_Location Value="12.0"...>
    p1 = rf'<{param_name}\s+[^>]*Value="([^"]+)"'
    for m in re.finditer(p1, xml_str, re.IGNORECASE):
        try: vals.append(float(m.group(1)))
        except ValueError: pass

    # Pattern 2: Tag contains the word (e.g., DesignLength for Length)
    p2 = rf'<[^>]*{param_name}[^>]*\s+Value="([^"]+)"'
    for m in re.finditer(p2, xml_str, re.IGNORECASE):
        try: vals.append(float(m.group(1)))
        except ValueError: pass
        
    # Pattern 3: Parm Name="..." Value="..."
    p3 = rf'<[^>]*(?:Name|ID)="{param_name}"[^>]*Value="([^"]+)"'
    for m in re.finditer(p3, xml_str, re.IGNORECASE):
        try: vals.append(float(m.group(1)))
        except ValueError: pass

    return vals


def verify_openvsp_evtol_boom(trajectory, env_info, task_info):
    result_file = task_info.get("metadata", {}).get(
        "result_file", "/tmp/openvsp_evtol_boom_result.json"
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

    # --- Check 1: File Integrity (10 pts) ---
    if not data.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "ecrm_evtol.vsp3 not found. Did you save the file to the correct location?",
        }

    content = data.get("file_content", "")
    content = content.replace("\\n", "\n").replace("\\t", "\t")

    try:
        root = ET.fromstring(content)
        score += 10
        feedback_parts.append("File is valid XML (+10)")
    except ET.ParseError as e:
        return {
            "passed": False,
            "score": 5,
            "feedback": f"ecrm_evtol.vsp3 is not valid XML: {e}",
        }

    # Extract Geoms
    geoms = root.findall('.//Geom')
    geom_names = [g.get('Name', '').lower() for g in geoms]

    # --- Check 2: Anti-Gaming Check (10 pts) ---
    # We must preserve the baseline model (Wing and Fuselage)
    has_wing = any('wing' in name for name in geom_names)
    has_fuse = any('fuselage' in name or 'body' in name for name in geom_names)
    if has_wing and has_fuse and len(geoms) >= 3:
        score += 10
        feedback_parts.append("Baseline components preserved (+10)")
    else:
        feedback_parts.append("Missing baseline components (Anti-gaming check failed) (+0)")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # --- Check 3: Component Creation (10 pts) ---
    boom_geom_node = None
    for g in geoms:
        name = g.get('Name', '').lower()
        if 'boom' in name:
            boom_geom_node = g
            break
            
    # Fallback if they didn't name it exactly right but added a new Pod/Fuselage
    if boom_geom_node is None:
        for g in geoms:
            name = g.get('Name', '').lower()
            type_name = g.get('TypeName', '').lower()
            if ('pod' in type_name or 'fuselage' in type_name) and ('fuselage' not in name):
                boom_geom_node = g
                break

    if boom_geom_node is not None:
        boom_name = boom_geom_node.get('Name', 'Unknown')
        if 'boom' in boom_name.lower():
            score += 10
            feedback_parts.append(f"Component named '{boom_name}' found (+10)")
        else:
            score += 5
            feedback_parts.append(f"New component found ('{boom_name}') but not named 'Boom' (+5)")
    else:
        feedback_parts.append("No Boom component found (+0)")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # Convert the isolated Boom component back to a string for regex extraction
    boom_xml_str = ET.tostring(boom_geom_node).decode('utf-8')

    # --- Target Constants ---
    T_LEN = 14.0
    T_DIA = 1.0
    T_Y = 8.5
    T_X = 12.0
    T_Z = 0.8

    # --- Check 4: Boom Length (15 pts) ---
    lengths = _get_values(boom_xml_str, "Length")
    best_len = min(lengths, key=lambda v: abs(v - T_LEN)) if lengths else None
    if best_len is not None and abs(best_len - T_LEN) <= 0.5:
        score += 15
        feedback_parts.append(f"Length correct ({best_len:.1f}m) (+15)")
    else:
        feedback_parts.append(f"Length incorrect or missing (found: {best_len}) (+0)")

    # --- Check 5: Boom Diameter (10 pts) ---
    diams = _get_values(boom_xml_str, "Width") + _get_values(boom_xml_str, "Diameter") + _get_values(boom_xml_str, "Height")
    best_dia = min(diams, key=lambda v: abs(v - T_DIA)) if diams else None
    if best_dia is not None and abs(best_dia - T_DIA) <= 0.2:
        score += 10
        feedback_parts.append(f"Diameter/Width correct ({best_dia:.1f}m) (+10)")
    else:
        feedback_parts.append(f"Diameter incorrect or missing (found: {best_dia}) (+0)")

    # --- Check 6: Spanwise Placement Y (15 pts) ---
    y_locs = _get_values(boom_xml_str, "Y_Location") + _get_values(boom_xml_str, "Y_Rel_Location")
    best_y = min(y_locs, key=lambda v: abs(v - T_Y)) if y_locs else None
    if best_y is not None and abs(best_y - T_Y) <= 0.2:
        score += 15
        feedback_parts.append(f"Y-Location correct ({best_y:.1f}m) (+15)")
    else:
        feedback_parts.append(f"Y-Location incorrect (found: {best_y}) (+0)")

    # --- Check 7: Fore/Aft Placement X (15 pts) ---
    x_locs = _get_values(boom_xml_str, "X_Location") + _get_values(boom_xml_str, "X_Rel_Location")
    best_x = min(x_locs, key=lambda v: abs(v - T_X)) if x_locs else None
    if best_x is not None and abs(best_x - T_X) <= 0.5:
        score += 15
        feedback_parts.append(f"X-Location correct ({best_x:.1f}m) (+15)")
    else:
        feedback_parts.append(f"X-Location incorrect (found: {best_x}) (+0)")

    # --- Check 8: Vertical Placement Z (10 pts) ---
    z_locs = _get_values(boom_xml_str, "Z_Location") + _get_values(boom_xml_str, "Z_Rel_Location")
    best_z = min(z_locs, key=lambda v: abs(v - T_Z)) if z_locs else None
    if best_z is not None and abs(best_z - T_Z) <= 0.2:
        score += 10
        feedback_parts.append(f"Z-Location correct ({best_z:.1f}m) (+10)")
    else:
        feedback_parts.append(f"Z-Location incorrect (found: {best_z}) (+0)")

    # --- Check 9: Symmetry (5 pts) ---
    syms = _get_values(boom_xml_str, "Sym")
    has_sym = any(v != 0 for v in syms)
    if has_sym:
        score += 5
        feedback_parts.append("Symmetry active (+5)")
    else:
        feedback_parts.append("Symmetry inactive (+0)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }