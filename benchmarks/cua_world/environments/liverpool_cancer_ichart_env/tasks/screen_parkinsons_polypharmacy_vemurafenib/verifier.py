#!/usr/bin/env python3
"""
Verifier for screen_parkinsons_polypharmacy_vemurafenib task.
"""

import json
import os
import re
import logging
from typing import Dict, Any, List

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_parkinsons_screen(traj, env_info, task_info):
    """
    Verifies the medication safety report for Vemurafenib + Parkinson's meds.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env missing"}

    # Load result JSON
    task_result = {}
    try:
        import tempfile
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            copy_from_env("/tmp/task_result.json", f.name)
            with open(f.name, 'r') as json_file:
                task_result = json.load(json_file)
            os.unlink(f.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {str(e)}"}

    # Load the report text content
    report_content = ""
    if task_result.get("report_exists"):
        try:
            with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as f:
                copy_from_env(task_result["report_local_path"], f.name)
                with open(f.name, 'r') as txt_file:
                    report_content = txt_file.read()
                os.unlink(f.name)
        except Exception as e:
            logger.warning(f"Could not read report file: {e}")

    # 2. Metadata & Criteria
    metadata = task_info.get("metadata", {})
    ropinirole_colors = metadata.get("ropinirole_color_candidates", ["red", "orange"])
    safe_colors = metadata.get("safe_color_candidates", ["green", "yellow", "grey"])
    
    score = 0
    feedback = []

    # Criterion 1: File Existence (10 pts)
    if task_result.get("report_exists") and len(report_content.strip()) > 0:
        score += 10
        feedback.append("Report file created.")
    else:
        return {"passed": False, "score": 0, "feedback": "Report file not found or empty."}

    # Criterion 2: Cancer Drug Identified (10 pts)
    if "vemurafenib" in report_content.lower():
        score += 10
        feedback.append("Cancer drug confirmed.")
    else:
        feedback.append("Report missing cancer drug 'Vemurafenib'.")

    # Criterion 3: Ropinirole Check (20 pts)
    # Check if Ropinirole is listed AND has a high-risk color
    ropinirole_match = re.search(r"ropinirole.*[:\s]+([a-zA-Z]+)", report_content, re.IGNORECASE)
    if ropinirole_match:
        color = ropinirole_match.group(1).lower()
        if color in ropinirole_colors:
            score += 20
            feedback.append(f"Ropinirole correctly identified as {color}.")
        else:
            score += 5 # Partial for listing it
            feedback.append(f"Ropinirole listed but wrong color '{color}' (expected Red/Orange).")
    else:
        feedback.append("Ropinirole not found in report.")

    # Criterion 4: Co-careldopa/Levodopa Check (20 pts)
    # Can be listed as Co-careldopa OR Levodopa
    levodopa_match = re.search(r"(co-careldopa|levodopa).*[:\s]+([a-zA-Z]+)", report_content, re.IGNORECASE)
    if levodopa_match:
        color = levodopa_match.group(2).lower()
        if color in safe_colors:
            score += 20
            feedback.append(f"Co-careldopa identified as {color}.")
        else:
            score += 5
            feedback.append(f"Co-careldopa listed but unexpected color '{color}'.")
    else:
        feedback.append("Co-careldopa (or Levodopa) not found in report.")

    # Criterion 5: Entacapone Check (20 pts)
    entacapone_match = re.search(r"entacapone.*[:\s]+([a-zA-Z]+)", report_content, re.IGNORECASE)
    if entacapone_match:
        color = entacapone_match.group(1).lower()
        if color in safe_colors:
            score += 20
            feedback.append(f"Entacapone identified as {color}.")
        else:
            score += 5
            feedback.append(f"Entacapone listed but unexpected color '{color}'.")
    else:
        feedback.append("Entacapone not found in report.")

    # Criterion 6: High Risk Identification (20 pts)
    high_risk_line = re.search(r"high risk.*[:\s]+([a-zA-Z\s]+)", report_content, re.IGNORECASE)
    if high_risk_line:
        culprit = high_risk_line.group(1).lower()
        if "ropinirole" in culprit:
            score += 20
            feedback.append("High risk drug correctly identified.")
        else:
            feedback.append(f"Incorrect high risk drug identified: {culprit}")
    else:
        feedback.append("High risk summary line missing.")

    # Secondary VLM Verification (Trajectory)
    # Ideally we would check trajectory frames here. 
    # Since we lack the VLM implementation in this snippet, we rely on file content heavily.
    # However, strict formatting requirements in regex act as a strong filter.
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }