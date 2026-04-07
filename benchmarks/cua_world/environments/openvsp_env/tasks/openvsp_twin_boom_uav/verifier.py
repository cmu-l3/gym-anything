#!/usr/bin/env python3
"""
Verifier for openvsp_twin_boom_uav task.

This verifier tests multiple independent criteria:
1. File exists and is valid XML (10 pts)
2. Central Pod component matches spec dimensions and position (20 pts)
3. Main Wing component matches spec dimensions and position (20 pts)
4. Tail Booms component(s) matches spec dimensions and off-axis position, and either symmetry is enabled or two booms exist (25 pts)
5. Horizontal Tail matches spec dimensions/position (15 pts)
6. Spatial Coherence constraint: Horizontal tail span must mathematically match boom separation (10 pts)

Pass threshold: 75 points.
"""

import json
import os
import re
import tempfile
import xml.etree.ElementTree as ET

def extract_components(xml_str):
    """
    Parses OpenVSP .vsp3 XML format using regex to gracefully handle structure variations.
    Extracts geometric properties from each <Component> block.
    """
    components = []
    parts = xml_str.split("<Component>")
    
    for part in parts[1:]:
        comp_str = part.split("</Component>")[0]
        comp = {}
        
        type_match = re.search(r'<Type>([^<]+)</Type>', comp_str)
        comp['type'] = type_match.group(1) if type_match else "Unknown"
        
        # OpenVSP stores parameters in tags like <Tag ... Value="X.XX"/>
        for tag in ['Length', 'TotalSpan', 'X_Rel_Location', 'Y_Rel_Location', 'Z_Rel_Location', 'X_Location', 'Y_Location', 'Sym_Planar_Flag']:
            val_match = re.search(rf'<{tag}\b[^>]*\bValue="([^"]+)"', comp_str)
            if val_match:
                try:
                    comp[tag] = float(val_match.group(1))
                except ValueError:
                    pass

        # Handle alternate format for symmetry flag
        if 'Sym_Planar_Flag' not in comp:
            sym_match = re.search(r'<Sym_Planar_Flag>([0-9]+)</Sym_Planar_Flag>', comp_str)
            if sym_match:
                try:
                    comp['Sym_Planar_Flag'] = float(sym_match.group(1))
                except ValueError:
                    pass
                    
        components.append(comp)
    return components


def verify_openvsp_twin_boom_uav(trajectory, env_info, task_info):
    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        env_info["copy_from_env"]("/tmp/task_result.json", local_tmp)
        with open(local_tmp, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file not found or invalid — export script may not have run: {e}"
        }
    finally:
        if os.path.exists(local_tmp):
            os.unlink(local_tmp)

    score = 0
    feedback_parts = []

    # --- Criterion 1: File Existence & Validity (10 pts) ---
    if not data.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "twin_boom_uav.vsp3 not found. The agent did not save the file correctly."
        }

    content = data.get("file_content", "")
    try:
        ET.fromstring(content)
        score += 10
        feedback_parts.append("File is valid XML (+10)")
    except ET.ParseError as e:
        return {
            "passed": False,
            "score": 5,
            "feedback": f"File exists but is not valid XML: {e}"
        }

    components = extract_components(content)
    
    # Sort into component categories
    fuselages = [c for c in components if 'Fuselage' in c['type'] or 'Pod' in c['type'] or 'BodyOfRevolution' in c['type']]
    wings = [c for c in components if 'Wing' in c['type']]

    # --- Criterion 2: Central Pod (20 pts) ---
    # Look for a fuselage ~3.4m long near the centerline (Y~0)
    pod = next((f for f in fuselages if 3.0 <= f.get('Length', 0) <= 3.8 and abs(f.get('Y_Location', f.get('Y_Rel_Location', 0))) < 0.2), None)
    if pod:
        score += 20
        feedback_parts.append("Central Pod configured correctly (+20)")
    else:
        feedback_parts.append("Central Pod missing or incorrect dimensions/position (+0)")

    # --- Criterion 3: Main Wing (20 pts) ---
    # Look for a wing with Span ~4.3m at X~1.0, centerline Y~0
    main_wing = next((w for w in wings if 3.8 <= w.get('TotalSpan', 0) <= 4.8 and 0.5 <= w.get('X_Location', w.get('X_Rel_Location', 0)) <= 1.5 and abs(w.get('Y_Location', w.get('Y_Rel_Location', 0))) < 0.2), None)
    if main_wing:
        score += 20
        feedback_parts.append("Main Wing configured correctly (+20)")
    else:
        feedback_parts.append("Main Wing missing or incorrect dimensions/position (+0)")

    # --- Criterion 4: Tail Booms (25 pts) ---
    # Look for fuselage(s) ~2.5m long at offset Y
    booms = [f for f in fuselages if 2.0 <= f.get('Length', 0) <= 3.0 and 0.4 <= abs(f.get('Y_Location', f.get('Y_Rel_Location', 0))) <= 0.9]
    boom_separation = 0
    boom_configured = False
    
    if booms:
        # Check for symmetry flag on a single boom
        for b in booms:
            if b.get('Sym_Planar_Flag', 0) > 0:
                boom_configured = True
                boom_separation = abs(b.get('Y_Location', b.get('Y_Rel_Location', 0))) * 2
                break
        
        # Alternatively, check if two distinct booms were created explicitly (Y and -Y)
        if not boom_configured and len(booms) >= 2:
            y1 = booms[0].get('Y_Location', booms[0].get('Y_Rel_Location', 0))
            y2 = booms[1].get('Y_Location', booms[1].get('Y_Rel_Location', 0))
            if y1 * y2 < 0:  # one is positive, one is negative
                boom_configured = True
                boom_separation = abs(y1 - y2)
                
        if boom_configured:
            score += 25
            feedback_parts.append(f"Tail Booms configured with pairing/symmetry (separation: {boom_separation:.2f}m) (+25)")
        else:
            # Single boom created without mirroring
            score += 15
            boom_separation = abs(booms[0].get('Y_Location', booms[0].get('Y_Rel_Location', 0))) * 2
            feedback_parts.append("Tail Boom found but missing opposite pair/symmetry (+15)")
    else:
        feedback_parts.append("Tail Booms missing or incorrect (+0)")

    # --- Criterion 5: Horizontal Tail (15 pts) ---
    # Look for a wing with Span ~1.3m translated aft to X~3.5m
    h_tail = next((w for w in wings if 1.0 <= w.get('TotalSpan', 0) <= 1.6 and 2.5 <= w.get('X_Location', w.get('X_Rel_Location', 0)) <= 4.5), None)
    
    if h_tail:
        score += 15
        feedback_parts.append("Horizontal Tail configured correctly (+15)")
        
        h_tail_span = h_tail.get('TotalSpan', 0)
        
        # --- Criterion 6: Spatial Coherence Check (10 pts) ---
        # The span of the horizontal tail should mathematically bridge the off-axis separation of the tail booms
        if boom_separation > 0 and abs(h_tail_span - boom_separation) < 0.1:
            score += 10
            feedback_parts.append(f"Spatial Coherence Valid: H-Tail span ({h_tail_span:.2f}m) bridges booms exactly (+10)")
        elif boom_separation > 0:
            feedback_parts.append(f"Spatial Coherence Failed: H-Tail span ({h_tail_span:.2f}m) does NOT match Boom separation ({boom_separation:.2f}m) (+0)")
        else:
            feedback_parts.append("Spatial Coherence check skipped (Booms not configured) (+0)")
    else:
        feedback_parts.append("Horizontal Tail missing or incorrect (+0)")

    # Pass condition based on achieving the majority of the components
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }