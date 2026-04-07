#!/usr/bin/env python3
"""
Verifier for openvsp_shuttle_stack_integration task.

Evaluates the saved sts_ascent_stack.vsp3 XML file for:
1. Valid Save & Baseline Retention: File exists, is valid XML, and has >= 3 components. (15 pts)
2. External Tank (ET):
   - Created & Sized: Length in [45.0, 49.0] m (20 pts)
   - Positioned: X in [6.0, 10.0] m, Z in [-8.0, -5.0] m (15 pts)
3. Solid Rocket Boosters (SRB):
   - Created & Sized: Length in [43.0, 47.0] m (20 pts)
   - Positioned: X in [6.5, 10.5] m, |Y| in [5.0, 7.5] m, Z in [-8.0, -5.0] m (15 pts)
   - Symmetry: SRB component has Y-Symmetry flag enabled OR two distinct SRBs exist (15 pts)

Total points: 100. Pass threshold: 70.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Geometric criteria
ET_LEN_RANGE = (45.0, 49.0)
ET_X_RANGE = (6.0, 10.0)
ET_Z_RANGE = (-8.0, -5.0)
ET_Y_RANGE = (-1.0, 1.0)

SRB_LEN_RANGE = (43.0, 47.0)
SRB_X_RANGE = (6.5, 10.5)
SRB_Z_RANGE = (-8.0, -5.0)
SRB_Y_ABS_RANGE = (5.0, 7.5)


def parse_vsp3_geoms(xml_content: str) -> list[dict]:
    """
    Robustly parses OpenVSP .vsp3 XML to extract properties for all <Geom> components.
    Uses regex to avoid strict namespace/format crashes, extracting <Tag Value="X"> pairs.
    """
    geoms = []
    # Split by <Geom to isolate component blocks
    parts = xml_content.split('<Geom')
    for part in parts[1:]:
        props = {}
        # Find all parameter values within this Geom block
        for m in re.finditer(r'<(\w+)\s+[^>]*Value="([^"]+)"', part):
            tag = m.group(1)
            val = m.group(2)
            try:
                props[tag] = float(val)
            except ValueError:
                pass
        geoms.append(props)
    return geoms


def get_length(props: dict) -> float:
    """Safely extracts the dominant length metric for a generic body component."""
    return props.get("Length", props.get("Design_Length", 0.0))


def verify_openvsp_shuttle_stack(traj, env_info, task_info):
    result_file = task_info.get("metadata", {}).get(
        "result_file", "/tmp/openvsp_shuttle_result.json"
    )

    # Use copy_from_env to get the result payload safely
    local_tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    local_tmp.close()
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available in environment."}

    try:
        copy_from_env(result_file, local_tmp.name)
        with open(local_tmp.name, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file not found or invalid — export script may have failed: {e}",
        }
    finally:
        if os.path.exists(local_tmp.name):
            os.unlink(local_tmp.name)

    score = 0
    feedback_parts = []

    # --- 1. Valid Save & Baseline Retention (15 pts) ---
    if not data.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "sts_ascent_stack.vsp3 not found. Agent did not save the final model."
        }
        
    xml_content = data.get("file_content", "")
    geoms = parse_vsp3_geoms(xml_content)
    
    if len(geoms) >= 3:
        score += 15
        feedback_parts.append(f"Model saved successfully with {len(geoms)} components (+15).")
    elif len(geoms) > 0:
        score += 5
        feedback_parts.append(f"Model saved but only contains {len(geoms)} components (likely overwrote baseline) (+5).")
    else:
        feedback_parts.append("Model contains no valid geometry components (+0).")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # --- 2. ET Evaluation ---
    et_candidate = None
    for g in geoms:
        length = get_length(g)
        y_loc = g.get("Y_Rel_Location", 0.0)
        if ET_LEN_RANGE[0] <= length <= ET_LEN_RANGE[1] and ET_Y_RANGE[0] <= y_loc <= ET_Y_RANGE[1]:
            et_candidate = g
            break
            
    if et_candidate:
        score += 20
        feedback_parts.append(f"ET created and sized correctly (L={get_length(et_candidate):.1f}m) (+20).")
        
        # Check ET Position
        et_x = et_candidate.get("X_Rel_Location", 0.0)
        et_z = et_candidate.get("Z_Rel_Location", 0.0)
        
        pos_score = 0
        if ET_X_RANGE[0] <= et_x <= ET_X_RANGE[1]:
            pos_score += 7.5
        if ET_Z_RANGE[0] <= et_z <= ET_Z_RANGE[1]:
            pos_score += 7.5
            
        score += pos_score
        feedback_parts.append(f"ET position evaluation: X={et_x:.1f}, Z={et_z:.1f} (+{pos_score:.1f}).")
    else:
        feedback_parts.append("No component matching ET dimensions/position found (+0).")

    # --- 3. SRB Evaluation ---
    srb_candidates = []
    for g in geoms:
        length = get_length(g)
        y_loc = abs(g.get("Y_Rel_Location", 0.0))
        if SRB_LEN_RANGE[0] <= length <= SRB_LEN_RANGE[1] and SRB_Y_ABS_RANGE[0] <= y_loc <= SRB_Y_ABS_RANGE[1]:
            srb_candidates.append(g)
            
    if srb_candidates:
        score += 20
        primary_srb = srb_candidates[0]
        feedback_parts.append(f"SRB created and sized correctly (L={get_length(primary_srb):.1f}m) (+20).")
        
        # Check SRB Position
        srb_x = primary_srb.get("X_Rel_Location", 0.0)
        srb_z = primary_srb.get("Z_Rel_Location", 0.0)
        
        pos_score = 0
        if SRB_X_RANGE[0] <= srb_x <= SRB_X_RANGE[1]:
            pos_score += 7.5
        if SRB_Z_RANGE[0] <= srb_z <= SRB_Z_RANGE[1]:
            pos_score += 7.5
            
        score += pos_score
        feedback_parts.append(f"SRB position evaluation: X={srb_x:.1f}, Z={srb_z:.1f} (+{pos_score:.1f}).")
        
        # Check SRB Symmetry
        sym_y = primary_srb.get("Sym_Y_Flag", 0.0)
        sym_planar = primary_srb.get("Sym_Planar_Flag", 0.0)
        
        if sym_y == 1.0 or sym_planar == 1.0:
            score += 15
            feedback_parts.append("SRB Y-Symmetry flag enabled (+15).")
        elif len(srb_candidates) >= 2:
            score += 15
            feedback_parts.append("Two distinct SRB components found (Manual Symmetry) (+15).")
        else:
            feedback_parts.append("Only one SRB found and symmetry flag is off (+0).")
    else:
        feedback_parts.append("No component matching SRB dimensions/position found (+0).")

    passed = score >= 70
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }