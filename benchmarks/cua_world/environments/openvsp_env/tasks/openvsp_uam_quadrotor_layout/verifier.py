#!/usr/bin/env python3
"""
Verifier for openvsp_uam_quadrotor_layout task.

Checks the agent created a valid OpenVSP quadrotor model with:
  1. File exists, is valid XML, and was created during task: 10 pts
  2. Fuselage or Pod component present: 10 pts
  3. Exactly 4 explicit Propeller components (no cheating with symmetry): 20 pts
  4. Rotor Sizing: Diameter is around 6.52 m: 15 pts
  5. Vertical Orientation: Pitch (Y_Rel_Rot) is near 90 or -90 deg: 25 pts
  6. Quadrant Layout: X, Y = ±3.26: 20 pts

Pass threshold: 70
"""

import json
import os
import re
import tempfile
import xml.etree.ElementTree as ET


def _extract_val(block: str, tag: str) -> float:
    """Extract a float Value for a given tag from a block of XML text."""
    # Matches <Tag Value="1.23"/> OR <Parm Name="Tag" Value="1.23"/>
    pattern1 = rf'<{tag}\s+[^>]*Value="([^"]+)"'
    pattern2 = rf'<Parm\s+Name="{tag}"\s+[^>]*Value="([^"]+)"'
    
    m1 = re.search(pattern1, block)
    if m1:
        try: return float(m1.group(1))
        except ValueError: pass
        
    m2 = re.search(pattern2, block)
    if m2:
        try: return float(m2.group(1))
        except ValueError: pass
        
    return None


def verify_openvsp_uam_quadrotor_layout(trajectory, env_info, task_info):
    result_file = task_info.get("metadata", {}).get(
        "result_file", "/tmp/openvsp_uam_quadrotor_layout_result.json"
    )

    copy_from_env = env_info.get('copy_from_env')
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

    # --- Check 1: File exists & created during task (10 pts) ---
    if not data.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "nasa_quadrotor.vsp3 not found at /home/ga/Documents/OpenVSP/nasa_quadrotor.vsp3."
        }

    if data.get("created_during_task", False):
        feedback_parts.append("File created/modified during task.")
    else:
        feedback_parts.append("Warning: File timestamp predates task start.")

    content = data.get("file_content", "")
    content = content.replace("\\n", "\n").replace("\\t", "\t")

    try:
        ET.fromstring(content)
        score += 10
        feedback_parts.append("File is valid XML (+10).")
    except ET.ParseError as e:
        return {
            "passed": False,
            "score": 5,
            "feedback": f"nasa_quadrotor.vsp3 is not valid XML: {e}"
        }

    # --- Parse Geometry Blocks ---
    geom_blocks = re.split(r'<Geom\b', content)[1:]
    
    propellers = []
    has_fuselage = False
    
    for block in geom_blocks:
        type_match = re.search(r'<TypeName>([^<]+)</TypeName>', block)
        type_name = type_match.group(1).lower() if type_match else ""
        
        if 'fuse' in type_name or 'pod' in type_name or 'body' in type_name:
            has_fuselage = True
            
        if 'prop' in type_name:
            prop_data = {
                'diameter': _extract_val(block, 'Diameter'),
                'x_loc': _extract_val(block, 'X_Rel_Location'),
                'y_loc': _extract_val(block, 'Y_Rel_Location'),
                'z_loc': _extract_val(block, 'Z_Rel_Location'),
                'y_rot': _extract_val(block, 'Y_Rel_Rot')
            }
            propellers.append(prop_data)

    # --- Check 2: Fuselage/Pod present (10 pts) ---
    if has_fuselage:
        score += 10
        feedback_parts.append("Fuselage/Pod component found (+10).")
    else:
        feedback_parts.append("No Fuselage or Pod component found (+0).")

    # --- Check 3: Exactly 4 distinct Propeller components (20 pts) ---
    num_props = len(propellers)
    if num_props == 4:
        score += 20
        feedback_parts.append("Exactly 4 distinct Propeller components found (+20).")
    elif num_props > 0:
        partial = min(15, num_props * 3)
        score += partial
        feedback_parts.append(f"Found {num_props} Propeller(s) instead of 4 (+{partial}).")
    else:
        feedback_parts.append("No Propeller components found (+0).")

    # --- Check 4, 5, 6: Sizing, Orientation, and Layout ---
    if num_props > 0:
        correct_diameters = 0
        correct_orientations = 0
        
        quadrants_filled = set()
        
        for p in propellers:
            # Diameter check: [6.0, 7.0]
            diam = p['diameter']
            if diam is not None and 6.0 <= diam <= 7.0:
                correct_diameters += 1
                
            # Vertical orientation check (Pitch/Y_Rot): near 90 or -90
            y_rot = p['y_rot']
            if y_rot is not None and (abs(y_rot - 90.0) <= 5.0 or abs(y_rot + 90.0) <= 5.0):
                correct_orientations += 1
                
            # Quadrant location check
            x = p['x_loc']
            y = p['y_loc']
            if x is not None and y is not None:
                if abs(abs(x) - 3.26) <= 0.5 and abs(abs(y) - 3.26) <= 0.5:
                    # Determine quadrant (+1/-1)
                    q_x = 1 if x > 0 else -1
                    q_y = 1 if y > 0 else -1
                    quadrants_filled.add((q_x, q_y))

        # Score Sizing (15 pts max)
        sizing_score = int((correct_diameters / max(4, num_props)) * 15)
        score += sizing_score
        feedback_parts.append(f"{correct_diameters}/{num_props} rotors sized correctly (+{sizing_score}).")

        # Score Orientation (25 pts max)
        orientation_score = int((correct_orientations / max(4, num_props)) * 25)
        score += orientation_score
        feedback_parts.append(f"{correct_orientations}/{num_props} rotors pitched vertically (+{orientation_score}).")

        # Score Quadrants (20 pts max)
        quadrants_score = int((len(quadrants_filled) / 4) * 20)
        score += quadrants_score
        feedback_parts.append(f"{len(quadrants_filled)}/4 quadrants correctly populated (+{quadrants_score}).")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }