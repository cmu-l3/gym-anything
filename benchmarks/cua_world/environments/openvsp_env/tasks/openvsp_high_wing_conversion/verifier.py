#!/usr/bin/env python3
"""
Verifier for openvsp_high_wing_conversion task.

Programmatically parses the saved OpenVSP XML files to verify the configuration change.

Verification Criteria:
1. eCRM001_highwing.vsp3 exists and is parseable XML (10 pts)
2. WingGeom component remains present (10 pts)
3. Z-Location moved upward significantly (differs from baseline by >= 1.0 m) (15 pts)
4. Z-Location falls within high-wing target range [1.5, 4.0] m (25 pts)
5. Outboard Dihedral adjusted to [-3.0, 2.0]° (25 pts)
6. Wing span remains within ±10% of baseline (15 pts) - Anti-gaming measure

Pass threshold: 60 points.
"""

import json
import os
import re
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def extract_wing_params(xml_content: str):
    """
    Regex-based parser to extract critical Wing parameters from OpenVSP 3 XML.
    Returns: (z_location, list_of_dihedrals, total_span)
    """
    # Find all <Geom> blocks
    geom_blocks = re.findall(r'<Geom>.*?</Geom>', xml_content, re.DOTALL)
    
    for block in geom_blocks:
        # Check if it's the main Wing component
        if '<Type>Wing</Type>' in block:
            
            # Extract Z_Location
            z_locs = re.findall(r'<Z_Location\s+Value="([^"]+)"', block)
            z_loc = float(z_locs[0]) if z_locs else 0.0
            
            # Extract Dihedrals (a wing may have multiple sections, thus multiple dihedrals)
            dihedrals = re.findall(r'<Dihedral\s+Value="([^"]+)"', block)
            dihedral_vals = [float(d) for d in dihedrals]
            
            # Extract TotalSpan
            spans = re.findall(r'<TotalSpan\s+Value="([^"]+)"', block)
            span = float(spans[0]) if spans else 0.0
            
            return z_loc, dihedral_vals, span
            
    return None, [], None

def verify_openvsp_high_wing_conversion(trajectory, env_info, task_info):
    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", "/tmp/high_wing_result.json")
    target_z = metadata.get("target_z_range", [1.5, 4.0])
    target_dih = metadata.get("target_dihedral_range", [-3.0, 2.0])

    copy_from_env = env_info.get("copy_from_env")
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
            "feedback": f"Failed to retrieve or read result JSON: {e}"
        }
    finally:
        if os.path.exists(local_tmp):
            os.unlink(local_tmp)

    score = 0
    feedback_parts = []
    
    # 1. Check File Existence & Validity (10 pts)
    if not data.get("modified_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "eCRM001_highwing.vsp3 not found. Agent may not have saved the file correctly."
        }

    mod_content = data.get("modified_content", "").replace("\\n", "\n").replace("\\t", "\t")
    base_content = data.get("baseline_content", "").replace("\\n", "\n").replace("\\t", "\t")
    
    try:
        ET.fromstring(mod_content)
        score += 10
        feedback_parts.append("Valid OpenVSP XML (+10)")
    except ET.ParseError as e:
        return {
            "passed": False,
            "score": 5,
            "feedback": f"Output is not valid XML: {e}"
        }

    # Extract parameters
    base_z, base_dih, base_span = extract_wing_params(base_content)
    mod_z, mod_dih, mod_span = extract_wing_params(mod_content)

    # 2. Check WingGeom presence (10 pts)
    if mod_z is None:
        feedback_parts.append("Wing component not found in saved file (+0)")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
    else:
        score += 10
        feedback_parts.append("Wing component found (+10)")

    # 3. Z-Location Change Anti-gaming (15 pts)
    if base_z is not None and abs(mod_z - base_z) >= 1.0:
        score += 15
        feedback_parts.append(f"Z-Location moved by >= 1.0m (Base: {base_z:.2f}, Mod: {mod_z:.2f}) (+15)")
    else:
        feedback_parts.append(f"Z-Location not changed significantly from baseline (Base: {base_z}, Mod: {mod_z}) (+0)")

    # 4. Z-Location in target range (25 pts)
    if target_z[0] <= mod_z <= target_z[1]:
        score += 25
        feedback_parts.append(f"Z-Location is in high-wing range [{target_z[0]}, {target_z[1]}] (+25)")
    else:
        feedback_parts.append(f"Z-Location {mod_z:.2f} is outside target range [{target_z[0]}, {target_z[1]}] (+0)")

    # 5. Dihedral adjustment (25 pts)
    # Check if ANY section's dihedral falls in the target range (since real wings have multiple sections)
    dih_in_range = False
    for d in mod_dih:
        if target_dih[0] <= d <= target_dih[1]:
            dih_in_range = True
            break
            
    if dih_in_range:
        score += 25
        feedback_parts.append(f"Dihedral adjusted to target range [{target_dih[0]}, {target_dih[1]}] (+25)")
    else:
        feedback_parts.append(f"No wing section dihedral found in target range [{target_dih[0]}, {target_dih[1]}] (+0)")

    # 6. Span preservation (15 pts)
    if base_span is not None and mod_span is not None:
        if abs(mod_span - base_span) / base_span <= 0.10:
            score += 15
            feedback_parts.append("Wing span preserved (+15)")
        else:
            feedback_parts.append(f"Wing span was incorrectly modified (Base: {base_span:.2f}, Mod: {mod_span:.2f}) (+0)")
    else:
        feedback_parts.append("Could not verify wing span preservation (+0)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }