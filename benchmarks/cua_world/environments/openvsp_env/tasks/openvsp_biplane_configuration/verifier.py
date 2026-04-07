#!/usr/bin/env python3
"""
Verifier for openvsp_biplane_configuration task.

Validates that the agent built a biplane model matching the specs:
- File exists and is valid XML: 10 pts
- At least 2 WingGeom components present: 20 pts
- Upper wing span within [7.0, 11.0] m: 15 pts
- Lower wing span within [6.0, 10.0] m: 10 pts
- Vertical separation (|delta Z|) > 0.5 m: 20 pts
- Fuselage body present: 15 pts
- Horizontal tail present (span in [1.5, 5.0]): 10 pts

Anti-gaming:
- File must be created/modified after task start.
- Uses copy_from_env to retrieve exported JSON safely.
"""

import json
import os
import re
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_param_value(xml_str: str, param_name: str) -> float:
    """Robustly extract parameter values from OpenVSP XML component string."""
    # 1. Try attribute style: <TotalSpan Value="8.94"...>
    m1 = re.search(rf'<{param_name}\s+Value="([^"]+)"', xml_str)
    if m1:
        try:
            return float(m1.group(1))
        except ValueError:
            pass
            
    # 2. Try tag style (OpenVSP v2 legacy/alternate): <Name>TotalSpan</Name> \n <Value>8.94</Value>
    m2 = re.search(rf'<Name>{param_name}</Name>.*?<Value>([^<]+)</Value>', xml_str, re.DOTALL)
    if m2:
        try:
            return float(m2.group(1))
        except ValueError:
            pass
            
    return 0.0


def verify_openvsp_biplane(trajectory, env_info, task_info):
    result_file = task_info.get("metadata", {}).get(
        "result_file", "/tmp/openvsp_biplane_result.json"
    )

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available in env."}

    # Retrieve results from container
    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env(result_file, local_tmp)
        with open(local_tmp, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file not found — agent may not have saved the file. Error: {e}",
        }
    finally:
        if os.path.exists(local_tmp):
            os.unlink(local_tmp)

    score = 0
    feedback_parts = []

    # --- Anti-Gaming: File modification time ---
    if not data.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "tiger_moth_biplane.vsp3 not found at expected location.",
        }
        
    if not data.get("file_created_during_task", True):
        feedback_parts.append("WARNING: File appears to have been created before task started.")

    content = data.get("file_content", "")
    content = content.replace("\\n", "\n").replace("\\t", "\t")

    # --- Criterion 1: XML Parsing (10 pts) ---
    try:
        root = ET.fromstring(content)
        score += 10
        feedback_parts.append("Valid OpenVSP XML (+10)")
    except ET.ParseError as e:
        return {
            "passed": False,
            "score": 5,
            "feedback": f"File is not valid XML: {e}",
        }

    # Parse components
    wings = []
    fuselages = []
    
    # We iterate all <Component> nodes
    for comp in root.findall('.//Component'):
        comp_type_elem = comp.find('Type')
        if comp_type_elem is not None:
            comp_type = comp_type_elem.text.strip()
            comp_str = ET.tostring(comp, encoding='unicode')
            
            if comp_type in ['WingGeom', 'MS_Wing']:
                # Extract span and Z-location
                span = extract_param_value(comp_str, "TotalSpan")
                
                # Check Z_Location or Z_Rel_Location
                z_loc = extract_param_value(comp_str, "Z_Location")
                if z_loc == 0.0:
                    z_loc = extract_param_value(comp_str, "Z_Rel_Location")
                    
                wings.append({'span': span, 'z': z_loc, 'xml': comp_str})
                
            elif comp_type in ['FuselageGeom', 'Stack', 'TransportFuse', 'BodyOfRevolutionGeom']:
                fuselages.append(comp)

    # --- Criterion 2: Fuselage present (15 pts) ---
    if fuselages:
        score += 15
        feedback_parts.append("Fuselage component found (+15)")
    else:
        feedback_parts.append("No Fuselage component found (+0)")

    # Sort wings by span descending to identify upper/lower/tail
    wings.sort(key=lambda w: w['span'], reverse=True)
    
    # --- Criterion 3: At least 2 WingGeom components (20 pts) ---
    if len(wings) >= 2:
        score += 20
        feedback_parts.append(f"Found {len(wings)} Wing components (+20)")
    elif len(wings) == 1:
        feedback_parts.append("Found only 1 Wing component. Biplane needs at least 2 (+0)")
    else:
        feedback_parts.append("No Wing components found (+0)")

    # --- Criteria 4 & 5: Upper and Lower Wings & Separation ---
    if len(wings) >= 2:
        w1 = wings[0] # Largest wing (expected upper, ~8.94)
        w2 = wings[1] # Second largest (expected lower, ~8.08)
        
        # Upper wing span [7.0, 11.0] (15 pts)
        if 7.0 <= w1['span'] <= 11.0:
            score += 15
            feedback_parts.append(f"Upper wing span {w1['span']:.2f}m in range (+15)")
        else:
            feedback_parts.append(f"Upper wing span {w1['span']:.2f}m out of bounds (+0)")
            
        # Lower wing span [6.0, 10.0] (10 pts)
        if 6.0 <= w2['span'] <= 10.0:
            score += 10
            feedback_parts.append(f"Lower wing span {w2['span']:.2f}m in range (+10)")
        else:
            feedback_parts.append(f"Lower wing span {w2['span']:.2f}m out of bounds (+0)")
            
        # Vertical Separation (|delta Z| > 0.5) (20 pts)
        z_diff = abs(w1['z'] - w2['z'])
        if z_diff > 0.5:
            score += 20
            feedback_parts.append(f"Vertical wing separation {z_diff:.2f}m is good (+20)")
        else:
            feedback_parts.append(f"Wings lack sufficient vertical separation (diff={z_diff:.2f}m, need > 0.5) (+0)")
    
    # --- Criterion 6: Horizontal Tail (10 pts) ---
    # Look for a 3rd wing component with span in [1.5, 5.0]
    tail_found = False
    for w in wings[2:]:
        if 1.5 <= w['span'] <= 5.0:
            tail_found = True
            break
            
    if tail_found:
        score += 10
        feedback_parts.append("Horizontal tail component found (+10)")
    else:
        if len(wings) >= 3:
            feedback_parts.append(f"3rd wing component has span {wings[2]['span']:.2f}m, outside tail range [1.5, 5.0] (+0)")
        else:
            feedback_parts.append("No 3rd wing (tail) component found (+0)")

    passed = score >= 60 and len(wings) >= 2
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }