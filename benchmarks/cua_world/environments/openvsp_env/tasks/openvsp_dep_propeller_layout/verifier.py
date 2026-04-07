#!/usr/bin/env python3
"""
Verifier for openvsp_dep_propeller_layout task.

Checks that the agent created a DEP model with:
  1. File Integrity: `dep_wing.vsp3` saved successfully and retains the baseline wing (10 pts)
  2. Component Count: At least 3 Propeller components exist in the model (20 pts)
  3. Propeller Geometry: Propellers have a diameter of ~0.8m and 3 blades (15 pts)
  4. Spanwise Positions (Y): Propellers are located at Y = 1.5m, 3.0m, and 4.5m (30 pts, 10 each)
  5. Chord/Vert Positions (X,Z): Propellers are located at X = -0.4m and Z = 0.0m (15 pts)
  6. Symmetry Configuration: XZ planar symmetry is enabled (10 pts)

Anti-gaming checks included: file modification timestamp validation.
Pass threshold: 70 points.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def get_parameter_value(block: str, param_name: str) -> float:
    """Extract parameter value robustly across OpenVSP XML formats."""
    # Format 1: <Diameter Value="0.800" ... /> or <X_Rel Value="-0.4" ... />
    pattern_direct = rf'<{param_name}(?:_Rel|_Location)?\s+Value="([^"]+)"'
    m_direct = re.search(pattern_direct, block)
    if m_direct:
        try:
            return float(m_direct.group(1))
        except ValueError:
            pass
            
    # Format 2: <Parm Name="Diameter" Value="0.800" ... />
    pattern_parm = rf'<Parm\s+Name="{param_name}"\s+[^>]*Value="([^"]+)"'
    m_parm = re.search(pattern_parm, block)
    if m_parm:
        try:
            return float(m_parm.group(1))
        except ValueError:
            pass
            
    return None


def verify_openvsp_dep_propeller_layout(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/openvsp_dep_propeller_layout_result.json')

    # Pull result file from environment
    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env(result_file, local_tmp)
        with open(local_tmp, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to retrieve or read result file: {e}"
        }
    finally:
        if os.path.exists(local_tmp):
            os.unlink(local_tmp)

    score = 0
    feedback_parts = []
    
    # --- Criterion 0: File Exists & Anti-Gaming ---
    if not data.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "dep_wing.vsp3 not found. Agent failed to save the model."
        }
        
    start_time = data.get("start_time", 0)
    mtime = data.get("mtime", 0)
    if mtime > 0 and start_time > 0 and mtime < start_time:
        return {
            "passed": False,
            "score": 0,
            "feedback": "File modification time is before task start time (Anti-gaming check failed)."
        }

    content = data.get("file_content", "").replace("\\n", "\n").replace("\\t", "\t")
    
    # --- Criterion 1: File Integrity & Wing Preservation (10 pts) ---
    if "<TypeName>Wing" in content:
        score += 10
        feedback_parts.append("Baseline wing preserved (+10).")
    else:
        feedback_parts.append("Baseline Wing missing (+0).")

    # Extract all Geometry blocks
    geom_blocks = re.findall(r'<Geom>.*?</Geom>', content, re.DOTALL)
    prop_blocks = [b for b in geom_blocks if '<TypeName>Prop' in b]

    # --- Criterion 2: Component Count (20 pts) ---
    prop_count = len(prop_blocks)
    if prop_count >= 3:
        score += 20
        feedback_parts.append(f"Found {prop_count} Propeller components (+20).")
    elif prop_count > 0:
        partial = prop_count * 6
        score += partial
        feedback_parts.append(f"Found only {prop_count} Propeller components (+{partial}).")
    else:
        feedback_parts.append("No Propeller components found (+0).")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Analyze Propeller Geometry & Location parameters
    diam_correct_cnt = 0
    blades_correct_cnt = 0
    x_correct_cnt = 0
    z_correct_cnt = 0
    sym_correct_cnt = 0
    y_values_found = []

    for block in prop_blocks:
        # Check Design
        diam = get_parameter_value(block, "Diameter")
        if diam is not None and abs(diam - 0.8) <= 0.05:
            diam_correct_cnt += 1
            
        blades = get_parameter_value(block, "NumBlade")
        if blades is not None and abs(blades - 3.0) < 0.1:
            blades_correct_cnt += 1
            
        # Check Location
        x_val = get_parameter_value(block, "X")
        if x_val is not None and abs(x_val - (-0.4)) <= 0.05:
            x_correct_cnt += 1
            
        y_val = get_parameter_value(block, "Y")
        if y_val is not None:
            y_values_found.append(y_val)
            
        z_val = get_parameter_value(block, "Z")
        if z_val is not None and abs(z_val - 0.0) <= 0.05:
            z_correct_cnt += 1
            
        # Check Symmetry (Planar XZ Flag)
        # Search for any planar symmetry flag activated (Value="1", "2", or "3" depending on VSP plane assignments)
        if re.search(r'<Sym_Planar[a-zA-Z0-9_]*\s+Value="[1-9]"', block):
            sym_correct_cnt += 1

    # --- Criterion 3: Propeller Geometry (15 pts) ---
    geom_score = min(15, (diam_correct_cnt * 2.5) + (blades_correct_cnt * 2.5))
    score += geom_score
    feedback_parts.append(f"Geometry check: {diam_correct_cnt} diams OK, {blades_correct_cnt} blades OK (+{geom_score:.1f}).")

    # --- Criterion 4: Spanwise Positions (Y) (30 pts) ---
    target_ys = [1.5, 3.0, 4.5]
    matched_ys = set()
    for y_val in y_values_found:
        for tgt in target_ys:
            if abs(y_val - tgt) <= 0.15 and tgt not in matched_ys:
                matched_ys.add(tgt)
                break
                
    y_score = len(matched_ys) * 10
    score += y_score
    feedback_parts.append(f"Y positions matched {len(matched_ys)}/3 targets (+{y_score}).")

    # --- Criterion 5: Chord/Vert Positions (X,Z) (15 pts) ---
    xz_score = min(15, (x_correct_cnt * 2.5) + (z_correct_cnt * 2.5))
    score += xz_score
    feedback_parts.append(f"X,Z positions check: {x_correct_cnt} X OK, {z_correct_cnt} Z OK (+{xz_score:.1f}).")

    # --- Criterion 6: Symmetry Configuration (10 pts) ---
    if sym_correct_cnt >= 3:
        score += 10
        feedback_parts.append("XZ Symmetry enabled on >=3 propellers (+10).")
    elif sym_correct_cnt > 0:
        sym_score = sym_correct_cnt * 3
        score += sym_score
        feedback_parts.append(f"XZ Symmetry enabled on {sym_correct_cnt} propellers (+{sym_score}).")
    else:
        feedback_parts.append("XZ Symmetry not enabled on propellers (+0).")

    score = min(100, int(score))
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }