#!/usr/bin/env python3
"""
Verifier for openvsp_longitudinal_stability_assessment task.

Verification Multi-Signal Strategy:
1. Model Saved & Xcg Updated (20 pts)
2. Report file exists and formatted (10 pts)
3. Authentic CMy values parsed from actual VSPAero .polar (20 pts)
   (Anti-hallucination check)
4. Mathematical accuracy of Cm_alpha derivation (20 pts)
5. Logical Status deduction (Stable vs Unstable) (15 pts)
6. VLM Trajectory check to confirm GUI usage (15 pts)

Total: 100 points. Pass threshold: 70.
"""

import json
import os
import re
import tempfile
import xml.etree.ElementTree as ET
from gym_anything.vlm import sample_trajectory_frames, query_vlm

def extract_polar_data(polar_content: str) -> dict:
    """Parse the .polar file to extract CMy at Alpha=0 and Alpha=4."""
    data = {}
    lines = polar_content.splitlines()
    header_idx = -1
    
    # Find header row
    for i, line in enumerate(lines):
        if line.startswith('#') and 'Alpha' in line and 'CMy' in line:
            header_idx = i
            break
            
    if header_idx == -1:
        return data
        
    headers = [h for h in lines[header_idx].strip('#').split() if h]
    try:
        alpha_col = headers.index('Alpha')
        cmy_col = headers.index('CMy')
    except ValueError:
        return data

    # Parse data rows
    for line in lines[header_idx+1:]:
        parts = line.split()
        if not parts or line.startswith('#'):
            continue
        try:
            alpha = float(parts[alpha_col])
            cmy = float(parts[cmy_col])
            # Check for alpha ~ 0.0 or ~ 4.0
            if abs(alpha - 0.0) < 0.1:
                data[0.0] = cmy
            elif abs(alpha - 4.0) < 0.1:
                data[4.0] = cmy
        except (ValueError, IndexError):
            continue
            
    return data

def verify_openvsp_longitudinal_stability(traj, env_info, task_info):
    result_file = task_info.get("metadata", {}).get(
        "result_file", "/tmp/openvsp_stability_result.json"
    )

    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        env_info["copy_from_env"](result_file, local_tmp)
        with open(local_tmp, "r") as f:
            data = json.load(f)
        os.unlink(local_tmp)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file not found — export script may not have run: {e}"
        }

    score = 0
    feedback_parts = []
    
    # Extract data
    model_exists = data.get("model_exists", False)
    model_content = data.get("model_content", "")
    polar_exists = data.get("polar_exists", False)
    polar_content = data.get("polar_content", "")
    report_exists = data.get("report_exists", False)
    report_content = data.get("report_content", "")
    task_start = data.get("task_start", 0)

    # -------------------------------------------------------------------------
    # Criterion 1: Model Saved & Xcg Updated (20 pts)
    # -------------------------------------------------------------------------
    xcg_correct = False
    if model_exists:
        # Check XML for Xcg modification
        try:
            # We look for <RefCG> block and then <X Value="...">
            # Or <Xcg Value="..."> depending on the exact OpenVSP version schema
            root = ET.fromstring(model_content)
            
            # Simple recursive search for Xcg values
            xcg_value = None
            
            # 1. Search for <RefCG> -> <X>
            for ref_cg in root.findall('.//RefCG'):
                x_el = ref_cg.find('X')
                if x_el is not None and 'Value' in x_el.attrib:
                    xcg_value = float(x_el.attrib['Value'])
                    
            # 2. Search for raw <Xcg> 
            if xcg_value is None:
                for xcg_el in root.findall('.//Xcg'):
                    if 'Value' in xcg_el.attrib:
                        xcg_value = float(xcg_el.attrib['Value'])
                        
            # Regex fallback
            if xcg_value is None:
                match = re.search(r'<RefCG>.*?<X\s+Value="([^"]+)"', model_content, re.DOTALL)
                if match:
                    xcg_value = float(match.group(1))

            if xcg_value is not None and abs(xcg_value - 28.5) < 0.1:
                xcg_correct = True
                score += 20
                feedback_parts.append("Model saved with Xcg=28.5 (+20)")
            else:
                feedback_parts.append(f"Model saved, but Xcg not set to 28.5 (found {xcg_value}) (+0)")
        except Exception as e:
            feedback_parts.append(f"Model exists but XML parsing failed (+0)")
    else:
        feedback_parts.append("eCRM-001_stability.vsp3 not saved (+0)")

    # -------------------------------------------------------------------------
    # Parse Report Values
    # -------------------------------------------------------------------------
    rep_cmy_0, rep_cmy_4, rep_cm_alpha, rep_status = None, None, None, None
    if report_exists:
        score += 10
        feedback_parts.append("Report file exists (+10)")
        
        # Regex extraction
        m0 = re.search(r'CMy.*Alpha\s*=?\s*0\s*:\s*([+-]?\d+\.?\d*(?:e[+-]?\d+)?)', report_content, re.IGNORECASE)
        m4 = re.search(r'CMy.*Alpha\s*=?\s*4\s*:\s*([+-]?\d+\.?\d*(?:e[+-]?\d+)?)', report_content, re.IGNORECASE)
        ma = re.search(r'Cm_alpha\s*:\s*([+-]?\d+\.?\d*(?:e[+-]?\d+)?)', report_content, re.IGNORECASE)
        ms = re.search(r'Status\s*:\s*(Stable|Unstable)', report_content, re.IGNORECASE)
        
        if m0: rep_cmy_0 = float(m0.group(1))
        if m4: rep_cmy_4 = float(m4.group(1))
        if ma: rep_cm_alpha = float(ma.group(1))
        if ms: rep_status = ms.group(1).title()
    else:
        feedback_parts.append("Report file missing (+0)")

    # -------------------------------------------------------------------------
    # Criterion 3: Authentic CMy values (Anti-hallucination) (20 pts)
    # -------------------------------------------------------------------------
    polar_cmy_0, polar_cmy_4 = None, None
    if polar_exists:
        polar_data = extract_polar_data(polar_content)
        polar_cmy_0 = polar_data.get(0.0)
        polar_cmy_4 = polar_data.get(4.0)
    
    values_authentic = False
    if polar_cmy_0 is not None and polar_cmy_4 is not None and rep_cmy_0 is not None and rep_cmy_4 is not None:
        # Allow small tolerance for rounding
        if abs(polar_cmy_0 - rep_cmy_0) < 0.005 and abs(polar_cmy_4 - rep_cmy_4) < 0.005:
            values_authentic = True
            score += 20
            feedback_parts.append("Reported CMy values match generated VSPAero data (+20)")
        else:
            feedback_parts.append(f"Reported CMy values ({rep_cmy_0}, {rep_cmy_4}) do not match actual data ({polar_cmy_0:.4f}, {polar_cmy_4:.4f}) (+0)")
    else:
        feedback_parts.append("Could not verify authenticity of CMy values (+0)")

    # -------------------------------------------------------------------------
    # Criterion 4: Mathematical accuracy of Cm_alpha (20 pts)
    # -------------------------------------------------------------------------
    math_correct = False
    if rep_cmy_0 is not None and rep_cmy_4 is not None and rep_cm_alpha is not None:
        expected_slope = (rep_cmy_4 - rep_cmy_0) / 4.0
        if abs(expected_slope - rep_cm_alpha) < 0.005:
            math_correct = True
            score += 20
            feedback_parts.append("Cm_alpha math is correct (+20)")
        else:
            feedback_parts.append(f"Cm_alpha math incorrect: expected {expected_slope:.4f}, got {rep_cm_alpha} (+0)")
    else:
        feedback_parts.append("Missing numerical values to verify math (+0)")

    # -------------------------------------------------------------------------
    # Criterion 5: Logical Status deduction (15 pts)
    # -------------------------------------------------------------------------
    status_correct = False
    if rep_cm_alpha is not None and rep_status is not None:
        expected_status = "Stable" if rep_cm_alpha < 0 else "Unstable"
        if rep_status == expected_status:
            status_correct = True
            score += 15
            feedback_parts.append(f"Status '{rep_status}' matches Cm_alpha sign (+15)")
        else:
            feedback_parts.append(f"Status '{rep_status}' contradicts Cm_alpha sign (+0)")
    else:
        feedback_parts.append("Missing Cm_alpha or Status to verify logic (+0)")

    # -------------------------------------------------------------------------
    # Criterion 6: VLM Trajectory Check (15 pts)
    # -------------------------------------------------------------------------
    vlm_points = 0
    if "query_vlm" in env_info:
        try:
            frames = sample_trajectory_frames(traj, n=5)
            prompt = (
                "You are evaluating an agent using OpenVSP. "
                "Does this trajectory show the agent opening the 'VSPAero' analysis window, "
                "interacting with the 'Reference' tab, and executing an aerodynamic sweep? "
                "Respond with YES if there is clear evidence of the VSPAero GUI being used, "
                "otherwise NO. No other text."
            )
            vlm_response = query_vlm(images=frames, prompt=prompt)
            if vlm_response.get("success") and "YES" in vlm_response.get("text", "").upper():
                vlm_points = 15
                score += vlm_points
                feedback_parts.append("VLM confirms VSPAero GUI usage (+15)")
            else:
                feedback_parts.append("VLM did not detect clear VSPAero GUI usage (+0)")
        except Exception as e:
            feedback_parts.append(f"VLM check failed: {e}")

    # Pass condition
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }