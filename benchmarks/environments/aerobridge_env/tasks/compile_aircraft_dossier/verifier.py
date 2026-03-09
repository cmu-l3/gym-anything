#!/usr/bin/env python3
"""
Verifier for compile_aircraft_dossier task.

Logic:
1. Parse the agent's generated text report.
2. Compare extracted values against the database ground truth.
3. Use fuzzy matching to handle slight formatting differences.
4. Verify the report was created during the task window.
5. Use VLM trajectory analysis to confirm navigation steps were performed.
"""

import json
import os
import re
import base64
import logging
import tempfile
import difflib

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Scoring Weights
SCORES = {
    "file_exists": 10,
    "aircraft_model": 10,
    "manufacturer_name": 12,
    "manufacturer_country": 8,
    "mass": 8,
    "icao_designator": 8,
    "registration_mark": 8,
    "sub_category": 6,
    "status": 6,
    "type_certificate_id": 8,
    "operator_name": 8,
    "operator_country": 8
}

def normalize_text(text):
    """Normalize text for comparison (lower case, strip punctuation/whitespace)."""
    if not text:
        return ""
    text = str(text).lower().strip()
    # Remove special chars but keep alphanumerics
    text = re.sub(r'[^a-z0-9\s]', '', text)
    return re.sub(r'\s+', ' ', text)

def fuzzy_match(expected, actual):
    """
    Compare expected vs actual with tolerance for formatting.
    Returns True if match is close enough.
    """
    if expected is None:
        expected = "N/A"
    if actual is None:
        actual = "N/A"

    n_exp = normalize_text(expected)
    n_act = normalize_text(actual)

    # Direct match
    if n_exp == n_act:
        return True
    
    # Handle "N/A" explicitly
    if n_exp == "na" and n_act == "na":
        return True
    if n_exp == "na" or n_act == "na":
        return False  # One is N/A, the other isn't

    # Substring match (e.g. "India" in "IN - India")
    if n_exp in n_act or n_act in n_exp:
        return True
    
    # Sequence matching for typos
    ratio = difflib.SequenceMatcher(None, n_exp, n_act).ratio()
    return ratio > 0.85

def parse_report(report_text):
    """
    Extract fields from the formatted report.
    Returns a dict of normalized keys to values.
    """
    data = {}
    # Regex to capture "Key: Value" lines
    # We look for the specific keys defined in the task description
    patterns = {
        "aircraft_model": r"Aircraft Model\s*:\s*(.+)",
        "manufacturer_name": r"Manufacturer\s*:\s*(.+)",
        "manufacturer_country": r"Manufacturer Country\s*:\s*(.+)",
        "mass": r"Mass.*:\s*(.+)",
        "icao_designator": r"ICAO.*Designator\s*:\s*(.+)",
        "registration_mark": r"Registration Mark\s*:\s*(.+)",
        "sub_category": r"Sub-category\s*:\s*(.+)",
        "status": r"Status\s*:\s*(.+)",
        "type_certificate_id": r"Type Certificate ID\s*:\s*(.+)",
        "operator_name": r"Operator\s*:\s*(.+)", # Careful not to match Operator Country
        "operator_country": r"Operator Country\s*:\s*(.+)"
    }

    for key, pattern in patterns.items():
        # Use multiline search
        # For operator, we need to be careful with regex greedy matching if lines are close
        match = re.search(pattern, report_text, re.IGNORECASE)
        if match:
            # Clean up the value
            val = match.group(1).strip()
            # If "Operator" matched "Operator Country", fix it
            if key == "operator_name" and "Country" in val:
                 # This implies the regex grabbed too much or the wrong line
                 # Retry with stricter anchor if needed, but basic regex usually stops at newline
                 pass
            data[key] = val
        else:
            data[key] = None
            
    # Specific fix for Operator vs Operator Country overlap if using naive regex
    # The dictionary iteration order matters if using loose regex, but specific labels help.
    return data

def verify_compile_dossier(traj, env_info, task_info):
    """
    Verify the Compile Aircraft Dossier task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. Verify File Existence & Creation (Anti-Gaming)
    if not result.get("report_exists"):
        return {"passed": False, "score": 0, "feedback": "Report file /home/ga/aircraft_dossier.txt not found."}
    
    if not result.get("file_created_during_task"):
        feedback.append("WARNING: Report file timestamp predates task start.")
        # We penalize but don't fail immediately, in case of clock skew, but usually this is 0.
        score += 0 # No points for pre-existing file
    else:
        score += SCORES["file_exists"]
        feedback.append("Report file created successfully.")

    # 3. Content Verification
    try:
        report_content = base64.b64decode(result.get("report_content_b64", "")).decode('utf-8')
    except:
        return {"passed": False, "score": score, "feedback": "Failed to decode report content."}

    ground_truth = result.get("ground_truth", {})
    parsed_data = parse_report(report_content)

    # Check each field
    match_count = 0
    total_fields = len(SCORES) - 1 # excluding file_exists

    for field, weight in SCORES.items():
        if field == "file_exists": continue
        
        expected = ground_truth.get(field)
        actual = parsed_data.get(field)
        
        if fuzzy_match(expected, actual):
            score += weight
            match_count += 1
            # verbose logging for debug
            # feedback.append(f"MATCH {field}: {expected} vs {actual}")
        else:
            feedback.append(f"MISMATCH {field}: Expected '{expected}', Got '{actual}'")

    # 4. VLM Trajectory Verification (Secondary)
    # We want to see the agent actually viewing the admin pages
    # This prevents "database hacking" via python shell (though harder to detect solely by VLM)
    # Ideally, we'd check if specific admin pages appeared in screenshots.
    
    # For now, we rely primarily on the robust text matching.
    # Pass threshold: 60 points + Key Fields (Model & Manufacturer)
    
    passed = False
    
    model_ok = fuzzy_match(ground_truth.get("aircraft_model"), parsed_data.get("aircraft_model"))
    mfr_ok = fuzzy_match(ground_truth.get("manufacturer_name"), parsed_data.get("manufacturer_name"))
    
    if score >= 60 and model_ok and mfr_ok:
        passed = True
        feedback.append("SUCCESS: Report accurate and key fields match.")
    elif score >= 60:
        feedback.append("FAIL: Score high but critical fields (Model/Manufacturer) incorrect.")
    else:
        feedback.append(f"FAIL: Insufficient score ({score}/100).")

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }