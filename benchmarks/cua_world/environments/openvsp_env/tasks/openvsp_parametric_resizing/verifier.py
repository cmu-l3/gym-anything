#!/usr/bin/env python3
"""
Verifier for openvsp_parametric_resizing task.

Parses the OpenVSP XML (.vsp3) files to verify that the agent parametrically
resized the wing and horizontal tail components to exact Area targets while 
strictly preserving the baseline Aspect Ratios.

Checks:
1. Resized file exists and was created/modified after task start (10 pts)
2. Fuselage length is unchanged (Anti-gaming global scale check) (10 pts)
3. Main Wing Area matches target 420.0 m^2 (25 pts)
4. Main Wing Aspect Ratio matches Baseline AR (15 pts)
5. Horizontal Tail Area matches target 105.0 m^2 (25 pts)
6. Horizontal Tail Aspect Ratio matches Baseline AR (15 pts)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_vsp3_components(content: str) -> list:
    """Extract component parameters safely using regex from OpenVSP XML."""
    components = []
    # Find all <Component> blocks
    comp_blocks = re.findall(r'<Component>(.*?)</Component>', content, re.DOTALL)
    
    for block in comp_blocks:
        type_match = re.search(r'<TypeName>([^<]+)</TypeName>', block)
        type_name = type_match.group(1) if type_match else "Unknown"
        
        name_match = re.search(r'<Name>([^<]+)</Name>', block)
        comp_name = name_match.group(1) if name_match else "Unnamed"
        
        def get_param(name):
            # Try <ParamName Value="X"/> format
            m = re.search(rf'<{name}\s+Value="([^"]+)"', block)
            if m:
                try: return float(m.group(1))
                except ValueError: pass
            
            # Try <Parm Name="ParamName" Value="X"/> format
            m = re.search(rf'<Parm\s+Name="{name}"[^>]*Value="([^"]+)"', block)
            if m:
                try: return float(m.group(1))
                except ValueError: pass
            return None

        components.append({
            'name': comp_name,
            'type': type_name,
            'TotalArea': get_param('TotalArea'),
            'TotalAR': get_param('TotalAR'),
            'Length': get_param('Length')
        })
    return components

def identify_key_components(components: list):
    """Identify the MainWing, HTail, and Fuselage from a list of components."""
    wings = [c for c in components if 'Wing' in c['type'] and c['TotalArea'] is not None]
    # Sort wings by area descending
    wings.sort(key=lambda x: x['TotalArea'], reverse=True)
    
    main_wing = wings[0] if len(wings) > 0 else None
    htail = wings[1] if len(wings) > 1 else None
    
    fuses = [c for c in components if c['type'] in ('Fuselage', 'Pod', 'FuselageGeom', 'PodGeom') and c['Length'] is not None]
    fuses.sort(key=lambda x: x['Length'], reverse=True)
    fuselage = fuses[0] if fuses else None
    
    return main_wing, htail, fuselage

def verify_openvsp_parametric_resizing(trajectory, env_info, task_info):
    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", "/tmp/openvsp_parametric_resizing_result.json")
    
    target_main_area = metadata.get("expected_main_area", 420.0)
    target_htail_area = metadata.get("expected_htail_area", 105.0)
    area_tol = metadata.get("area_tolerance", 2.0)
    ar_tol = metadata.get("ar_tolerance", 0.05)
    fuse_tol = metadata.get("fuselage_tolerance", 0.1)

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verifier copy function missing."}

    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env(result_file, local_tmp)
        with open(local_tmp, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to retrieve result file: {e}"
        }
    finally:
        if os.path.exists(local_tmp):
            os.unlink(local_tmp)

    score = 0
    feedback_parts = []

    # --- Check 1: File Existence & Anti-Gaming Timestamp (10 pts) ---
    if not data.get("resized_exists", False):
        return {"passed": False, "score": 0, "feedback": "Resized model file not found."}
    
    if data.get("resized_mtime", 0) < data.get("task_start", 0):
        feedback_parts.append("Warning: Model file timestamp predates task start (might not have been saved properly).")
    else:
        score += 10
        feedback_parts.append("Resized file saved (+10).")

    # Extract components
    base_comps = parse_vsp3_components(data.get("baseline_content", ""))
    base_wing, base_htail, base_fuse = identify_key_components(base_comps)
    
    res_comps = parse_vsp3_components(data.get("resized_content", ""))
    res_wing, res_htail, res_fuse = identify_key_components(res_comps)

    if not base_wing or not res_wing:
        feedback_parts.append("Could not identify Main Wing in baseline or resized model.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # --- Check 2: Fuselage Unchanged (10 pts) ---
    if base_fuse and res_fuse:
        base_L = base_fuse['Length']
        res_L = res_fuse['Length']
        if abs(base_L - res_L) <= fuse_tol:
            score += 10
            feedback_parts.append("Fuselage length unchanged (+10).")
        else:
            feedback_parts.append(f"Fuselage length changed! (Base: {base_L:.1f}, Resized: {res_L:.1f}) Global scale used? (+0).")
    else:
        feedback_parts.append("Could not find fuselage to verify.")

    # --- Check 3 & 4: Main Wing Resizing (40 pts) ---
    res_w_area = res_wing['TotalArea']
    res_w_ar = res_wing['TotalAR']
    base_w_ar = base_wing['TotalAR']
    
    if abs(res_w_area - target_main_area) <= area_tol:
        score += 25
        feedback_parts.append(f"Main Wing Area target met: {res_w_area:.1f} m^2 (+25).")
    else:
        feedback_parts.append(f"Main Wing Area {res_w_area:.1f} m^2 (Target: {target_main_area}) (+0).")

    if abs(res_w_ar - base_w_ar) <= ar_tol:
        score += 15
        feedback_parts.append(f"Main Wing Aspect Ratio preserved: {res_w_ar:.2f} (+15).")
    else:
        feedback_parts.append(f"Main Wing AR changed! Base: {base_w_ar:.2f}, Resized: {res_w_ar:.2f} (+0).")

    # --- Check 5 & 6: Horizontal Tail Resizing (40 pts) ---
    if base_htail and res_htail:
        res_h_area = res_htail['TotalArea']
        res_h_ar = res_htail['TotalAR']
        base_h_ar = base_htail['TotalAR']
        
        if abs(res_h_area - target_htail_area) <= area_tol:
            score += 25
            feedback_parts.append(f"HTail Area target met: {res_h_area:.1f} m^2 (+25).")
        else:
            feedback_parts.append(f"HTail Area {res_h_area:.1f} m^2 (Target: {target_htail_area}) (+0).")

        if abs(res_h_ar - base_h_ar) <= ar_tol:
            score += 15
            feedback_parts.append(f"HTail Aspect Ratio preserved: {res_h_ar:.2f} (+15).")
        else:
            feedback_parts.append(f"HTail AR changed! Base: {base_h_ar:.2f}, Resized: {res_h_ar:.2f} (+0).")
    else:
        feedback_parts.append("Could not identify Horizontal Tail in model.")

    passed = score >= 80  # Strict pass threshold, expects both Area and AR to be correct for at least one surface
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }