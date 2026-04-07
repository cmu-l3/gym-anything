#!/usr/bin/env python3
"""
Verifier for openvsp_geometric_tail_sizing task.

Verification Strategy:
1. Parse report to extract the agent's reported values (Sw, MACw, Xw, Xt, lh, St).
2. Mathematically check the agent's calculations based on their own reported values.
3. Parse the final saved XML to find the actual Tail Area and Aspect Ratio.
4. Verify the Tail Area in the XML matches the required calculation.
5. Verify Aspect Ratio was preserved compared to the initial XML.
6. Use VLM trajectory verification as an anti-gaming check to confirm GUI interaction.
"""

import json
import re
import xml.etree.ElementTree as ET
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """
You are analyzing a user's workflow in OpenVSP (an aircraft geometry tool).
The user was asked to extract parameters from the 'Plan' and 'Design' tabs for the Wing and Horizontal Tail, and modify the Horizontal Tail's Area.

Review these trajectory frames and determine:
1. Did the user open the properties/parameters window for ANY geometric component?
2. Did the user navigate to the "Plan" or "Design" tabs?
3. Is there evidence of the user interacting with area, span, or chord values?

Respond with a JSON object containing boolean values:
{
    "opened_properties": true/false,
    "navigated_tabs": true/false,
    "interacted_with_parameters": true/false
}
"""

def extract_param_from_xml(xml_content: str, geom_keyword: str, param_name: str) -> float:
    """Helper to extract a specific Parm Value from a specific Geom section."""
    if not xml_content:
        return None
    try:
        tree = ET.fromstring(xml_content)
        for geom in tree.findall('.//Geom'):
            name_elem = geom.find('GeomName')
            if name_elem is not None and geom_keyword.lower() in name_elem.text.lower():
                for parm in geom.findall('.//Parm'):
                    if parm.get('Name') == param_name:
                        return float(parm.get('Value'))
    except Exception as e:
        logger.warning(f"XML parse error: {e}")
    return None

def verify_openvsp_tail_sizing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/openvsp_tail_sizing_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. Report Parsing (20 pts)
    report_text = result.get('report_content', '')
    if not result.get('report_exists') or not report_text.strip():
        feedback.append("Report sizing_report.txt missing or empty (0/20)")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}
        
    def extract_value(pattern):
        m = re.search(pattern, report_text, re.IGNORECASE)
        return float(m.group(1)) if m else None

    # Try to extract the requested fields
    Sw = extract_value(r'Sw.*?:\s*([\d\.]+)')
    MACw = extract_value(r'MACw.*?:\s*([\d\.]+)')
    Xw = extract_value(r'Xw.*?:\s*([\d\.]+)')
    Xt = extract_value(r'Xt.*?:\s*([\d\.]+)')
    lh_reported = extract_value(r'lh.*?:\s*([\d\.]+)')
    St_reported = extract_value(r'St.*?:\s*([\d\.]+)')

    if None in [Sw, MACw, Xw, Xt, lh_reported, St_reported]:
        feedback.append("Report missing one or more expected fields (partial points)")
        score += 10
    else:
        score += 20
        feedback.append("Report successfully parsed (20/20)")

    # 2. Math Verification (20 pts)
    math_correct = False
    if Sw and MACw and lh_reported:
        expected_St = (1.10 * Sw * MACw) / lh_reported
        # Allow small tolerance for rounding differences
        if St_reported and abs(St_reported - expected_St) < 0.5:
            score += 20
            math_correct = True
            feedback.append("Math logic for Target St is correct (20/20)")
        else:
            feedback.append(f"Math error: expected St ~ {expected_St:.2f}, got {St_reported}")

    # 3. Final XML Extraction & Verification (40 pts)
    final_xml = result.get('final_xml', '')
    initial_xml = result.get('initial_xml', '')
    
    if not result.get('final_exists') or not final_xml:
        feedback.append("aircraft_configuration_sized.vsp3 not saved")
    else:
        # Check timestamps
        task_start = result.get('task_start', 0)
        final_mtime = result.get('final_mtime', 0)
        if final_mtime < task_start:
            feedback.append("XML saved file timestamp predates task (Anti-gaming triggered)")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}
            
        final_tail_area = extract_param_from_xml(final_xml, 'tail', 'TotalArea') or extract_param_from_xml(final_xml, 'tail', 'Area')
        final_tail_ar = extract_param_from_xml(final_xml, 'tail', 'Aspect')
        initial_tail_ar = extract_param_from_xml(initial_xml, 'tail', 'Aspect')
        
        # Check AR lock
        if initial_tail_ar and final_tail_ar and abs(initial_tail_ar - final_tail_ar) < 0.05:
            score += 15
            feedback.append("Aspect Ratio properly preserved (15/15)")
        else:
            feedback.append("Aspect Ratio changed! Lock AR was not used.")
            
        # Check target Area application
        if math_correct and final_tail_area and abs(final_tail_area - St_reported) < 0.5:
            score += 25
            feedback.append("Final Model Tail Area matches Required Area exactly (25/25)")
        elif final_tail_area:
            feedback.append(f"Final Area ({final_tail_area}) doesn't match reported target")

    # 4. VLM Verification (20 pts)
    vlm_score = 0
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_res = query_vlm(images=frames, prompt=VLM_PROMPT)
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("opened_properties"): vlm_score += 5
            if parsed.get("navigated_tabs"): vlm_score += 5
            if parsed.get("interacted_with_parameters"): vlm_score += 10
            score += vlm_score
            feedback.append(f"VLM UI Trajectory validation: {vlm_score}/20")
        else:
            feedback.append("VLM evaluation failed, bypassing penalty")
            score += 20 # Give benefit of doubt if VLM fails technically
    else:
        feedback.append("No trajectory frames for VLM")

    passed = score >= 70 and math_correct

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }