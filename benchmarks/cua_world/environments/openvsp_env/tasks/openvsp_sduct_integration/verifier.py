#!/usr/bin/env python3
"""
Verifier for openvsp_sduct_integration task.

Evaluates the agent's ability to:
1. Create a `Duct` component (named Center_S_Duct).
2. Position it spatially (X location, Length).
3. Modify inner `XSec` (cross-section) parameters to create an S-curve (`Z_Offset` drop).

Anti-gaming:
- The `bizjet_trijet.vsp3` file MUST be created/modified during the task run.
- File must be valid XML.
"""

import json
import os
import re
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_openvsp_sduct_integration(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    x_loc_range = metadata.get("x_loc_range", [15.0, 17.0])
    length_range = metadata.get("length_range", [4.0, 5.0])
    z_offset_diff_min = metadata.get("z_offset_diff_min", 1.0)
    expected_name = metadata.get("expected_name", "Center_S_Duct").lower()

    # Pull result file from VM
    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env("/tmp/openvsp_sduct_result.json", local_tmp)
        with open(local_tmp, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file not found or corrupted: {e}"
        }
    finally:
        if os.path.exists(local_tmp):
            os.unlink(local_tmp)

    score = 0
    feedback_parts = []

    # --- Criterion 1: File Existence & Anti-Gaming (10 pts) ---
    if not data.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "bizjet_trijet.vsp3 not found. Agent did not save the file correctly."
        }

    if not data.get("file_created_during_task", False):
        feedback_parts.append("File modification time predates task start (possible gaming).")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }
    
    score += 10
    feedback_parts.append("Valid file created during task (+10)")

    # Validate XML
    content = data.get("file_content", "")
    try:
        ET.fromstring(content)
    except ET.ParseError as e:
        return {
            "passed": False,
            "score": score,
            "feedback": f"bizjet_trijet.vsp3 is not valid XML: {e}"
        }

    # --- XML Parsing for OpenVSP Logic ---
    # Safely isolate <Geom> blocks to avoid regex cross-matching
    geom_blocks = content.split('<Geom>')
    duct_block = None

    # Find the Duct component
    for block in geom_blocks:
        if '<Type>Duct</Type>' in block:
            duct_block = block
            break

    # --- Criterion 2: Duct Component Exists (20 pts) ---
    if duct_block is None:
        feedback_parts.append("No Duct component found in the model.")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
    
    # Check Name
    name_match = re.search(r'<Name>(.*?)</Name>', duct_block)
    actual_name = name_match.group(1).lower() if name_match else ""
    if expected_name in actual_name or "duct" in actual_name:
        score += 20
        feedback_parts.append(f"Duct component found ('{actual_name}') (+20)")
    else:
        # Partial credit if they added a duct but named it wrong
        score += 10
        feedback_parts.append(f"Duct component found, but wrongly named '{actual_name}' (+10)")

    # --- Criterion 3: Duct Global X Placement (20 pts) ---
    x_loc_match = re.search(r'<X_Location\s+Value="([^"]+)"', duct_block)
    if x_loc_match:
        try:
            x_loc = float(x_loc_match.group(1))
            if x_loc_range[0] <= x_loc <= x_loc_range[1]:
                score += 20
                feedback_parts.append(f"X_Location correct ({x_loc:.1f} m) (+20)")
            else:
                feedback_parts.append(f"X_Location out of range ({x_loc:.1f} m)")
        except ValueError:
            feedback_parts.append("Failed to parse X_Location.")
    else:
        feedback_parts.append("X_Location not found in Duct parameters.")

    # --- Criterion 4: Duct Length (20 pts) ---
    length_match = re.search(r'<Length\s+Value="([^"]+)"', duct_block)
    if length_match:
        try:
            length = float(length_match.group(1))
            if length_range[0] <= length <= length_range[1]:
                score += 20
                feedback_parts.append(f"Length correct ({length:.1f} m) (+20)")
            else:
                feedback_parts.append(f"Length out of range ({length:.1f} m)")
        except ValueError:
            feedback_parts.append("Failed to parse Length.")
    else:
        feedback_parts.append("Length not found in Duct parameters.")

    # --- Criterion 5: S-Curve Geometry via Z_Offset (30 pts) ---
    z_offsets = []
    # Find all Z_Offset values within the Duct's cross-section specifications
    for match in re.finditer(r'<Z_Offset\s+Value="([^"]+)"', duct_block):
        try:
            z_offsets.append(float(match.group(1)))
        except ValueError:
            pass
            
    if len(z_offsets) >= 2:
        inlet_z = z_offsets[0]
        exit_z = z_offsets[-1]
        diff = inlet_z - exit_z
        
        if diff >= z_offset_diff_min:
            score += 30
            feedback_parts.append(f"S-Curve established (Inlet Z: {inlet_z:.1f}, Exit Z: {exit_z:.1f}, Diff: {diff:.1f}) (+30)")
        else:
            feedback_parts.append(f"S-Curve too shallow or inverted (Inlet Z: {inlet_z:.1f}, Exit Z: {exit_z:.1f})")
    else:
        feedback_parts.append("Could not find enough Z_Offsets to evaluate S-curve.")

    # Pass threshold: Agent must successfully create duct, place it properly, and achieve the S-Curve.
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }