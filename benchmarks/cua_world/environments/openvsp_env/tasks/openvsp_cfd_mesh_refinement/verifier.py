#!/usr/bin/env python3
"""
Verifier for openvsp_cfd_mesh_refinement task.

Checks:
  1. Files (vsp3 and tri) exist and were created during the task. (15 pts)
  2. Global Max Edge Length is set near 0.40m. (15 pts)
  3. Source Box parameters (X, Y, Z, Length, Width, Height) are configured. (30 pts)
  4. Source Target Edge Length is set near 0.05m. (20 pts)
  5. The generated mesh reflects multi-resolution mapping via triangle count check. (20 pts)
     - A pure 0.40m mesh is ~15k tris.
     - A pure 0.05m mesh is ~500k+ tris.
     - The multi-resolution box around the tail yields roughly 60,000 to 250,000 tris.
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_all_parms(xml_content):
    """Parse all <Parm> tags and extract their Name and Value as a list of dicts."""
    parms = []
    try:
        root = ET.fromstring(xml_content)
        for parm in root.findall(".//Parm"):
            name = parm.get("Name")
            value = parm.get("Value")
            if name and value is not None:
                try:
                    parms.append({"Name": name, "Value": float(value)})
                except ValueError:
                    pass
    except ET.ParseError:
        pass
    return parms

def has_value_near(parms, name, target, tol=1e-3):
    """Check if any parsed parameter with 'name' is within 'tol' of 'target'."""
    for p in parms:
        if p["Name"] == name and abs(p["Value"] - target) <= tol:
            return True
    return False

def verify_openvsp_cfd_mesh_refinement(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    t_global_edge = metadata.get('target_global_edge', 0.40)
    t_x = metadata.get('target_box_x', 52.0)
    t_y = metadata.get('target_box_y', 0.0)
    t_z = metadata.get('target_box_z', 5.0)
    t_l = metadata.get('target_box_l', 10.0)
    t_w = metadata.get('target_box_w', 18.0)
    t_h = metadata.get('target_box_h', 8.0)
    t_src_edge = metadata.get('target_source_edge', 0.05)
    t_tri_min = metadata.get('target_tri_min', 60000)
    t_tri_max = metadata.get('target_tri_max', 250000)

    # 1. Fetch JSON result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/openvsp_cfd_mesh_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Check File Existence & Anti-Gaming
    vsp3_ok = result.get('vsp3_exists', False) and result.get('vsp3_created_during_task', False)
    tri_ok = result.get('tri_exists', False) and result.get('tri_created_during_task', False)

    if vsp3_ok and tri_ok:
        score += 15
        feedback_parts.append("VSP3 and TRI files saved correctly (+15)")
    elif vsp3_ok:
        score += 8
        feedback_parts.append("VSP3 file saved, but TRI export missing (+8)")
    else:
        feedback_parts.append("VSP3 project file not saved properly (+0)")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Parse XML content
    xml_content = result.get('vsp3_content', '')
    parms = parse_all_parms(xml_content)
    if not parms:
        feedback_parts.append("Failed to parse parameters from VSP3 XML.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Check Global Edge
    # OpenVSP uses FarMaxEdgeLen, MaxEdgeLen, or similar for CFD.
    global_edge_found = False
    for p in parms:
        if "EdgeLen" in p["Name"] and abs(p["Value"] - t_global_edge) < 0.001:
            global_edge_found = True
            break
            
    if global_edge_found:
        score += 15
        feedback_parts.append("Global Max Edge Length configured (+15)")
    else:
        feedback_parts.append("Global Max Edge Length not found or incorrect (+0)")

    # Check Box Source (X, Y, Z, L, W, H)
    box_matches = 0
    if has_value_near(parms, "X", t_x): box_matches += 1
    if has_value_near(parms, "Y", t_y): box_matches += 1
    if has_value_near(parms, "Z", t_z): box_matches += 1
    if has_value_near(parms, "Length", t_l): box_matches += 1
    if has_value_near(parms, "Width", t_w): box_matches += 1
    if has_value_near(parms, "Height", t_h): box_matches += 1

    if box_matches == 6:
        score += 30
        feedback_parts.append("Source Box fully configured (+30)")
    else:
        pts = box_matches * 5
        score += pts
        feedback_parts.append(f"Source Box partially configured ({box_matches}/6 params) (+{pts})")

    # Check Source Target Edge
    source_edge_found = False
    for p in parms:
        # It's usually "TargetEdgeLen" or "MaxEdgeLen" for a source, check if *any* parameter matches 0.05
        if abs(p["Value"] - t_src_edge) < 0.001:
            source_edge_found = True
            break
            
    if source_edge_found:
        score += 20
        feedback_parts.append("Source Target Edge Length configured (+20)")
    else:
        feedback_parts.append("Source Target Edge Length not found or incorrect (+0)")

    # Check Tri Count
    tri_count = result.get('tri_count', 0)
    if tri_count == 0 and result.get('tri_size', 0) > 1000000:
        # Fallback if header parsing failed but file is reasonably large
        # 1MB is roughly 25k tris in Cart3D
        tri_count = result.get('tri_size', 0) // 40
        
    if t_tri_min <= tri_count <= t_tri_max:
        score += 20
        feedback_parts.append(f"Multi-resolution mesh generated properly ({tri_count} tris) (+20)")
    elif tri_count > 0:
        feedback_parts.append(f"Mesh generated, but triangle count ({tri_count}) outside multi-resolution band [{t_tri_min}-{t_tri_max}] (+0)")
    else:
        feedback_parts.append("Valid mesh not found or empty (+0)")

    # Pass logic: Must have configured the box source correctly and got reasonable score
    box_correct = box_matches >= 5
    passed = score >= 70 and box_correct

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }