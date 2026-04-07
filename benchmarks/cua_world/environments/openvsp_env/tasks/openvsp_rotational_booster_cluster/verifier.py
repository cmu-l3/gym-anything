#!/usr/bin/env python3
"""
Verifier for openvsp_rotational_booster_cluster task.

Verification Strategy (XML parsing):
1. File exists and was created during the task (anti-gaming timestamp check).
2. Contains a component named "Core".
3. Contains a component named "SRB".
4. SRB XForm Translation (X ~ 10.0, Y ~ 2.2).
5. SRB Length (~ 15.0).
6. SRB Rotational Symmetry is enabled with exactly 4 instances.
"""

import json
import os
import re
import tempfile
import xml.etree.ElementTree as ET

def extract_param_value(block: str, param_name: str) -> float:
    """Regex helper to reliably extract float values from OpenVSP XML blocks."""
    pattern = rf'<{param_name}\s+Value="([^"]+)"'
    match = re.search(pattern, block)
    if match:
        try:
            return float(match.group(1))
        except ValueError:
            pass
    return None

def verify_booster_cluster(trajectory, env_info, task_info):
    result_file = task_info.get("metadata", {}).get(
        "result_file", "/tmp/openvsp_rotational_booster_result.json"
    )

    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        env_info["copy_from_env"](result_file, local_tmp)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file missing. Export script failure: {e}"
        }

    with open(local_tmp, "r") as f:
        data = json.load(f)
    os.unlink(local_tmp)

    score = 0
    feedback_parts = []

    # 1. Base Anti-Gaming & Existence Checks (10 pts)
    if not data.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target file heavy_launch_vehicle.vsp3 was not found."
        }
    
    mtime = data.get("mtime", 0)
    task_start = data.get("task_start", 0)
    if mtime < task_start:
        return {
            "passed": False,
            "score": 0,
            "feedback": "File timestamp is older than task start. Do not use pre-existing files."
        }

    content = data.get("file_content", "").replace("\\n", "\n")
    try:
        ET.fromstring(content)
        score += 10
        feedback_parts.append("File is valid XML (+10).")
    except ET.ParseError:
        feedback_parts.append("File is not valid XML. Parameters cannot be evaluated.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Splitting into chunks by <Geom to isolate component-specific parameters safely
    geom_blocks = content.split('<Geom')
    core_block = None
    srb_block = None

    for block in geom_blocks:
        if '<Name>Core</Name>' in block or '<Name>core</Name>' in block.lower():
            core_block = '<Geom' + block
        if '<Name>SRB</Name>' in block or '<Name>srb</Name>' in block.lower():
            srb_block = '<Geom' + block

    # 2. Core Stage Check (10 pts)
    if core_block:
        score += 10
        feedback_parts.append("Core component found (+10).")
    else:
        feedback_parts.append("Core component missing (+0).")

    # 3. SRB Component Check (10 pts)
    if not srb_block:
        feedback_parts.append("SRB component missing (+0). Failing early.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    else:
        score += 10
        feedback_parts.append("SRB component found (+10).")

    # 4. SRB Length Check [13.5 to 16.5] (15 pts)
    srb_len = extract_param_value(srb_block, "Length")
    if srb_len is not None and 13.5 <= srb_len <= 16.5:
        score += 15
        feedback_parts.append(f"SRB Length correct ({srb_len:.1f}m) (+15).")
    else:
        feedback_parts.append(f"SRB Length incorrect (Expected ~15.0, Got {srb_len}) (+0).")

    # 5. SRB X-Translation [9.0 to 11.0] (15 pts)
    srb_x = extract_param_value(srb_block, "X_Rel_Location")
    if srb_x is not None and 9.0 <= srb_x <= 11.0:
        score += 15
        feedback_parts.append(f"SRB X-Offset correct ({srb_x:.1f}m) (+15).")
    else:
        feedback_parts.append(f"SRB X-Offset incorrect (Expected ~10.0, Got {srb_x}) (+0).")

    # 6. SRB Y-Translation [1.8 to 2.6] (10 pts)
    srb_y = extract_param_value(srb_block, "Y_Rel_Location")
    if srb_y is not None and 1.8 <= srb_y <= 2.6:
        score += 10
        feedback_parts.append(f"SRB Y-Offset correct ({srb_y:.1f}m) (+10).")
    else:
        feedback_parts.append(f"SRB Y-Offset incorrect (Expected ~2.2, Got {srb_y}) (+0).")

    # 7. Rotational Symmetry Check (15 pts)
    sym_rot_flag = extract_param_value(srb_block, "Sym_Rot_Flag")
    if sym_rot_flag is not None and sym_rot_flag >= 1.0:
        score += 15
        feedback_parts.append("SRB Rotational Symmetry enabled (+15).")
    else:
        feedback_parts.append("SRB Rotational Symmetry is disabled (+0).")

    # 8. Rotational Instance Count (15 pts)
    sym_rot_num = extract_param_value(srb_block, "Sym_Rot_Num")
    if sym_rot_num is not None and abs(sym_rot_num - 4.0) < 0.1:
        score += 15
        feedback_parts.append("SRB Rotational Instance Count is 4 (+15).")
    else:
        feedback_parts.append(f"SRB Rotational Instance Count incorrect (Got {sym_rot_num}) (+0).")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }