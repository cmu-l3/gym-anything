#!/usr/bin/env python3
import json
import os
import re
import tempfile
import xml.etree.ElementTree as ET

def verify_tandem_wing_uav(trajectory, env_info, task_info):
    """
    Verifies the tandem-wing UAV model created in OpenVSP.
    
    Checks for:
    1. Valid VSP3 XML creation
    2. Presence of a fuselage
    3. Presence of multiple wings with expected spans
    4. Longitudinal separation of the wings (tandem requirement)
    5. Presence of a vertical tail surface
    """
    result_file = task_info.get("metadata", {}).get(
        "result_file", "/tmp/openvsp_tandem_wing_uav_result.json"
    )

    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        env_info["copy_from_env"](result_file, local_tmp)
        with open(local_tmp, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file not found: {e}"
        }
    finally:
        if os.path.exists(local_tmp):
            os.unlink(local_tmp)

    score = 0
    feedback_parts = []

    file_exists = data.get("file_exists", False)
    mtime = data.get("mtime", 0)
    task_start = data.get("task_start", 0)
    
    if not file_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "tandem_wing_uav.vsp3 not found. The model was not saved to the correct path."
        }
    
    if mtime > 0 and task_start > 0 and mtime < task_start:
        feedback_parts.append("Warning: File modification time suggests file existed before task start.")

    content = data.get("file_content", "").replace("\\n", "\n")
    
    # Check 1: Valid XML
    try:
        ET.fromstring(content)
        score += 10
        feedback_parts.append("File is valid XML (+10).")
    except ET.ParseError as e:
        feedback_parts.append(f"File is not valid XML: {e}")

    # Parse components out of the XML using regex block extraction
    blocks = re.findall(r'<Geom\b[^>]*>(.*?)</Geom>', content, re.DOTALL)
    
    geoms = []
    for block in blocks:
        geom = {}
        # Get Component Type
        type_m = re.search(r'<Type>([^<]+)</Type>', block)
        geom['type'] = type_m.group(1).strip() if type_m else 'Unknown'
        
        # Get Component Name
        name_m = re.search(r'<Name>([^<]+)</Name>', block)
        geom['name'] = name_m.group(1).strip() if name_m else 'Unknown'
        
        # Get Span (Look for TotalSpan, fallback to Span)
        span_m = re.search(r'<TotalSpan\b[^>]*Value="([^"]+)"', block)
        if not span_m:
            span_m = re.search(r'<Span\b[^>]*Value="([^"]+)"', block)
        try:
            geom['span'] = float(span_m.group(1)) if span_m else 0.0
        except ValueError:
            geom['span'] = 0.0
            
        # Get X Location (Look for X_Rel_Location or X_Location)
        x_m = re.search(r'<X_Rel_Location\b[^>]*Value="([^"]+)"', block)
        if not x_m:
            x_m = re.search(r'<X_Location\b[^>]*Value="([^"]+)"', block)
        try:
            geom['x_loc'] = float(x_m.group(1)) if x_m else 0.0
        except ValueError:
            geom['x_loc'] = 0.0
            
        geoms.append(geom)

    # Check 2: Fuselage present (10 pts)
    fuselage_types = ['Fuselage', 'Pod', 'BodyOfRevolution', 'Stack', 'TransStack']
    has_fuselage = any(g['type'] in fuselage_types for g in geoms)
    if not has_fuselage:
        # Fallback to checking names if type isn't standard
        has_fuselage = any('fuse' in g['name'].lower() or 'body' in g['name'].lower() for g in geoms)
        
    if has_fuselage:
        score += 10
        feedback_parts.append("Fuselage component found (+10).")
    else:
        feedback_parts.append("No Fuselage component found.")

    # Get Wing components
    wings = [g for g in geoms if g['type'] == 'Wing']
    
    # Check 3: Two or more wings (15 pts)
    if len(wings) >= 2:
        score += 15
        feedback_parts.append(f"Found {len(wings)} Wing components (+15).")
    else:
        feedback_parts.append(f"Found only {len(wings)} Wing components (need at least 2).")

    # Check 4: Correct Wing Spans (15 pts each)
    fwd_range = task_info.get("metadata", {}).get("fwd_wing_span_range", [4.5, 7.5])
    aft_range = task_info.get("metadata", {}).get("aft_wing_span_range", [6.5, 10.0])
    
    fwd_found = False
    aft_found = False
    fwd_wing = None
    aft_wing = None
    
    # Map wings into forward and aft categories by matching spans
    for w in wings:
        span = w['span']
        if not fwd_found and fwd_range[0] <= span <= fwd_range[1]:
            fwd_found = True
            fwd_wing = w
            continue
        if not aft_found and aft_range[0] <= span <= aft_range[1]:
            aft_found = True
            aft_wing = w
            continue

    if fwd_found:
        score += 15
        feedback_parts.append("Forward wing (span ~6m) correctly identified (+15).")
    else:
        feedback_parts.append(f"No wing with span in {fwd_range}m found.")
        
    if aft_found:
        score += 15
        feedback_parts.append("Aft wing (span ~8m) correctly identified (+15).")
    else:
        feedback_parts.append(f"No wing with span in {aft_range}m found.")

    # Check 5: Longitudinal Separation (20 pts)
    min_sep = task_info.get("metadata", {}).get("min_x_separation", 1.0)
    if fwd_wing and aft_wing:
        separation = abs(fwd_wing['x_loc'] - aft_wing['x_loc'])
        if separation > min_sep:
            score += 20
            feedback_parts.append(f"Wings separated longitudinally by {separation:.2f}m (+20).")
        else:
            feedback_parts.append(f"Wings lack longitudinal separation (ΔX = {separation:.2f}m <= {min_sep}m).")
    elif len(wings) >= 2:
        # Fallback: check separation of any two wings if exact spans missed
        w1, w2 = wings[0], wings[1]
        separation = abs(w1['x_loc'] - w2['x_loc'])
        if separation > min_sep:
            score += 20
            feedback_parts.append(f"Wings separated by {separation:.2f}m in X (partial match, +20).")
        else:
            feedback_parts.append("Wings lack proper longitudinal separation.")
    else:
        feedback_parts.append("Not enough wings to check separation.")

    # Check 6: Vertical Tail (10 pts)
    has_vtail = False
    for g in geoms:
        # Agent might name it directly
        if 'tail' in g['name'].lower() or 'vert' in g['name'].lower():
            has_vtail = True
            break
        # Agent might just use a very small Wing component
        if g['type'] == 'Wing' and 0.0 < g['span'] <= 2.0:
            has_vtail = True
            break
            
    if has_vtail:
        score += 10
        feedback_parts.append("Vertical tail identified (+10).")
    elif len(geoms) >= 4:
        score += 10
        feedback_parts.append("Assumed 4th component is vertical tail (+10).")
    else:
        feedback_parts.append("No vertical tail identified.")

    # Check 7: At least 4 components total (5 pts)
    valid_geoms = [g for g in geoms if g['type'] != 'Blank']
    if len(valid_geoms) >= 4:
        score += 5
        feedback_parts.append(f"Total valid components: {len(valid_geoms)} (>= 4) (+5).")
    else:
        feedback_parts.append(f"Total valid components: {len(valid_geoms)} (expected >= 4).")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }