#!/usr/bin/env python3
"""
Verifier for openvsp_wake_downwash_penalty task.

Checks:
  1. tandem_wake.vsp3 was created and saved (10 pts)
  2. Fuselage and Tail components stripped (15 pts)
  3. Lead wing was duplicated, resulting in exactly two Wing components (20 pts)
  4. Trail wing X_Location / Z_Location modified appropriately (20 pts)
  5. VSPAero solver executed over the model (20 pts)
  6. wake_penalty_report.txt contains numerical CL and CD outputs (15 pts)

Pass threshold: 65, ensuring duplication and core geometric changes were made.
"""

import json
import os
import re
import tempfile


def _find_param_values(content: str, param_name: str) -> list:
    """Extract float values for a specific OpenVSP parameter tag."""
    pattern = rf'<{param_name}\s+Value="([^"]+)"'
    vals = []
    for m in re.finditer(pattern, content):
        try:
            vals.append(float(m.group(1)))
        except ValueError:
            pass
    return vals


def verify_openvsp_wake_downwash_penalty(trajectory, env_info, task_info):
    result_file = task_info.get("metadata", {}).get(
        "result_file", "/tmp/openvsp_wake_downwash_penalty_result.json"
    )

    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        env_info["copy_from_env"](result_file, local_tmp)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file not found: {e}"
        }

    with open(local_tmp, "r") as f:
        data = json.load(f)
    os.unlink(local_tmp)

    score = 0
    feedback_parts = []
    wings = 0

    vsp3_exists = data.get("vsp3_exists", False)
    content = data.get("vsp3_content", "")
    
    if vsp3_exists:
        score += 10
        feedback_parts.append("tandem_wake.vsp3 created (+10)")
        
        # OpenVSP XML component type checking
        wings = len(re.findall(r'<Type>Wing</Type>', content))
        fuselages = len(re.findall(r'<Type>Fuselage</Type>|<Type>Pod</Type>|<Type>BodyOfRevolution</Type>', content))
        tails = len(re.findall(r'<Name>Horiz_Tail</Name>|<Name>Vert_Tail</Name>', content))
        
        # Criterion 2: Stripping irrelevant geometry
        if fuselages == 0 and tails == 0:
            score += 15
            feedback_parts.append("Fuselage and tail components correctly stripped (+15)")
        else:
            feedback_parts.append("Baseline components not fully stripped (+0)")
            
        # Criterion 3: Component duplication
        if wings == 2:
            score += 20
            feedback_parts.append("Exactly 2 Wing components found (+20)")
        elif wings > 0:
            feedback_parts.append(f"{wings} Wing components found, expected 2 (+0)")
        else:
            feedback_parts.append("No Wing components found in model (+0)")
            
        # Criterion 4: Exact Spatial Positioning verification 
        x_vals = _find_param_values(content, "X_Location") + _find_param_values(content, "X_Rel")
        z_vals = _find_param_values(content, "Z_Location") + _find_param_values(content, "Z_Rel")
        
        x_ok = any(abs(x - 75.0) <= 0.5 for x in x_vals)
        z_ok = any(abs(z - (-2.5)) <= 0.5 for z in z_vals)
        
        if x_ok and z_ok:
            score += 20
            feedback_parts.append("Trail wing positioned correctly at X=75, Z=-2.5 (+20)")
        elif x_ok:
            score += 10
            feedback_parts.append("Trail wing X position correct, but Z incorrect (+10)")
        elif z_ok:
            score += 10
            feedback_parts.append("Trail wing Z position correct, but X incorrect (+10)")
        else:
            feedback_parts.append("Trail wing spatial position incorrect (+0)")
    else:
        feedback_parts.append("tandem_wake.vsp3 not found (+0)")

    # Criterion 5: Aerodynamic computation execution
    if data.get("vspaero_run", False):
        score += 20
        feedback_parts.append("VSPAero analysis executed (+20)")
    else:
        feedback_parts.append("VSPAero results not found (+0)")
        
    # Criterion 6: Post-processing metrics reporting
    report_exists = data.get("report_exists", False)
    report_content = data.get("report_content", "")
    
    if report_exists:
        # Require presence of numeric data strings along with metric labels
        has_numbers = len(re.findall(r'[+-]?\d+\.\d+', report_content)) >= 2
        cl_mentioned = re.search(r'CL|lift|C_L', report_content, re.IGNORECASE)
        cd_mentioned = re.search(r'CD|drag|C_D', report_content, re.IGNORECASE)
        
        if has_numbers and (cl_mentioned or cd_mentioned):
            score += 15
            feedback_parts.append("Report contains numeric CL/CD values (+15)")
        else:
            feedback_parts.append("Report missing numeric CL/CD values (+0)")
    else:
        feedback_parts.append("wake_penalty_report.txt not found (+0)")

    # Logical passing metric ensuring geometric core integrity was satisfied
    passed = score >= 65 and wings == 2
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }