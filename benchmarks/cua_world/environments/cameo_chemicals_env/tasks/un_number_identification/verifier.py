#!/usr/bin/env python3
"""
Verifier for UN Number Identification Task.
Verifies that the agent correctly identified the chemical (Acrolein) from UN 1092
and extracted the correct physical/hazard properties from CAMEO Chemicals.
"""

import json
import os
import re
import tempfile
import logging
from typing import Dict, Any, List

# Import VLM utilities from framework
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    # Fallback for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def query_vlm(images, prompt): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_un_number_identification(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the UN identification task.
    
    Score breakdown (100 pts total):
    - File verification (55 pts total)
    - Data accuracy (40 pts total)
    - VLM workflow verification (5 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata and expected values
    metadata = task_info.get('metadata', {})
    expected = metadata.get('expected_values', {})
    report_path = metadata.get('output_file', '/home/ga/Documents/un1092_field_report.txt')

    score = 0
    feedback_parts = []
    
    # 1. Load result JSON
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}

    # 2. Check File Existence & Anti-Gaming (10 pts)
    if not task_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Report file not found"}
    
    score += 5
    feedback_parts.append("File exists (+5)")

    if task_result.get('file_created_during_task', False):
        score += 5
        feedback_parts.append("File created during task (+5)")
    else:
        feedback_parts.append("WARNING: File timestamps indicate pre-task creation (anti-gaming check failed)")

    # 3. Read and Parse Report Content
    content = ""
    with tempfile.NamedTemporaryFile(mode='w+', suffix='.txt') as f:
        try:
            copy_from_env(report_path, f.name)
            f.seek(0)
            content = f.read()
        except Exception as e:
            feedback_parts.append(f"Could not read report file: {e}")

    if not content:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts) + " (Empty file)"}

    # Normalize content for easier parsing
    lines = content.split('\n')
    data = {}
    for line in lines:
        if ':' in line:
            key, val = line.split(':', 1)
            data[key.strip().lower()] = val.strip()

    # 4. Verify Data Fields (85 pts max)
    
    # Helper for checking content
    def check_value(field_key, expected_pattern, points, name):
        val = data.get(field_key.lower())
        if not val:
            # Try fuzzy matching key
            for k, v in data.items():
                if field_key in k:
                    val = v
                    break
        
        if val and re.search(expected_pattern, val, re.IGNORECASE):
            return points, f"{name} correct (+{points})"
        return 0, f"{name} incorrect or missing"

    # Chemical Name (10 pts)
    p, msg = check_value("Chemical Name", r"acrolein|2-propenal|acrylaldehyde", 10, "Chemical Name")
    score += p
    feedback_parts.append(msg)

    # CAS Number (10 pts)
    p, msg = check_value("CAS Number", r"107-02-8", 10, "CAS Number")
    score += p
    feedback_parts.append(msg)

    # UN Number (5 pts)
    p, msg = check_value("UN/NA Number", r"1092", 5, "UN Number")
    score += p
    feedback_parts.append(msg)

    # DOT Hazard (10 pts)
    p, msg = check_value("DOT Hazard Class", r"6\.1", 10, "DOT Class")
    score += p
    feedback_parts.append(msg)

    # ERG Guide (10 pts)
    p, msg = check_value("ERG Guide Number", r"131", 10, "ERG Guide")
    score += p
    feedback_parts.append(msg)

    # NFPA Ratings (5 pts each)
    p, msg = check_value("NFPA Health", r"4", 5, "NFPA Health")
    score += p; feedback_parts.append(msg)
    
    p, msg = check_value("NFPA Fire", r"3", 5, "NFPA Fire")
    score += p; feedback_parts.append(msg)
    
    p, msg = check_value("NFPA Instability", r"[23]", 5, "NFPA Instability")
    score += p; feedback_parts.append(msg)

    # Numeric Range Checks helper
    def extract_number(text):
        if not text: return None
        matches = re.findall(r"[-+]?\d*\.\d+|\d+", text)
        return float(matches[0]) if matches else None

    # Boiling Point (8 pts)
    bp_val = extract_number(data.get("boiling point", ""))
    # Look for fuzzy key match
    if bp_val is None:
        for k, v in data.items():
            if "boiling" in k: bp_val = extract_number(v); break

    if bp_val is not None and ((50 <= bp_val <= 56) or (122 <= bp_val <= 133)):
        score += 8
        feedback_parts.append("Boiling Point correct (+8)")
    else:
        feedback_parts.append("Boiling Point out of range or missing")

    # Flash Point (8 pts)
    fp_val = extract_number(data.get("flash point", ""))
    if fp_val is None:
        for k, v in data.items():
            if "flash" in k: fp_val = extract_number(v); break
            
    if fp_val is not None and ((-30 <= fp_val <= -15) or (-22 <= fp_val <= 4)):
        score += 8
        feedback_parts.append("Flash Point correct (+8)")
    else:
        feedback_parts.append("Flash Point out of range or missing")

    # Vapor Density (5 pts)
    vd_val = extract_number(data.get("vapor density", ""))
    if vd_val is None:
        for k, v in data.items():
            if "vapor" in k and "density" in k: vd_val = extract_number(v); break

    if vd_val is not None and (1.8 <= vd_val <= 2.1):
        score += 5
        feedback_parts.append("Vapor Density correct (+5)")
    else:
        feedback_parts.append("Vapor Density out of range or missing")

    # Molecular Weight (5 pts)
    mw_val = extract_number(data.get("molecular weight", ""))
    if mw_val is None:
        for k, v in data.items():
            if "molecular" in k or "weight" in k: mw_val = extract_number(v); break
            
    if mw_val is not None and (55 <= mw_val <= 58):
        score += 5
        feedback_parts.append("Molecular Weight correct (+5)")
    else:
        feedback_parts.append("Molecular Weight out of range or missing")

    # Chemical Formula (4 pts)
    p, msg = check_value("Chemical Formula", r"C3H4O|CH2CHCHO|C3H4O", 4, "Formula")
    score += p
    feedback_parts.append(msg)

    # 5. VLM Trajectory Verification (5 pts)
    # Check if agent actually used the website
    frames = sample_trajectory_frames(traj, n=4)
    vlm_score = 0
    
    if frames:
        prompt = """
        Did the user navigate the CAMEO Chemicals website?
        Look for:
        1. A search bar or search results
        2. Chemical information page (Acrolein or UN 1092)
        3. Physical properties tables
        
        Answer JSON: {"navigated_cameo": bool, "found_target": bool}
        """
        try:
            result = query_vlm(images=frames, prompt=prompt)
            parsed = result.get('parsed', {})
            if parsed.get('navigated_cameo'):
                vlm_score += 3
            if parsed.get('found_target'):
                vlm_score += 2
        except Exception:
            # Fallback if VLM fails but file is correct
            if score > 50: vlm_score = 5
    
    if vlm_score > 0:
        score += vlm_score
        feedback_parts.append(f"Visual verification passed (+{vlm_score})")

    # Final result
    passed = score >= 60
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }