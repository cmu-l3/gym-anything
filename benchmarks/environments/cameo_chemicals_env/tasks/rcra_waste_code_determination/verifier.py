#!/usr/bin/env python3
"""
Verifier for RCRA Hazardous Waste Code Determination task.
"""

import json
import os
import csv
import io
import base64
import logging
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_csv_content(b64_content: str) -> List[Dict[str, str]]:
    """Decodes and parses the CSV content."""
    try:
        decoded = base64.b64decode(b64_content).decode('utf-8', errors='replace')
        f = io.StringIO(decoded)
        reader = csv.DictReader(f)
        # Normalize column names to lowercase for robust matching
        normalized_rows = []
        for row in reader:
            normalized_row = {k.strip().lower(): v.strip() for k, v in row.items() if k}
            normalized_rows.append(normalized_row)
        return normalized_rows
    except Exception as e:
        logger.error(f"CSV Parsing Error: {e}")
        return []

def normalize_codes(code_str: str) -> set:
    """Parses codes like 'D001; D002' into a set {'D001', 'D002'}."""
    if not code_str or code_str.lower() == 'none':
        return set()
    # Replace common separators
    code_str = code_str.replace(',', ';')
    parts = code_str.split(';')
    return {p.strip().upper() for p in parts if p.strip()}

def verify_rcra_waste_code_determination(traj, env_info, task_info):
    """
    Verifies the RCRA waste code classification task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # 1. Retrieve Result JSON
    # Use copy_from_env to safely read /tmp/task_result.json
    import tempfile
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Check Basic Compliance
    if not result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output CSV file was not found."}

    if not result.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file existed before task start (Anti-gaming check failed)."}

    # 3. Parse Data
    rows = parse_csv_content(result.get("output_content_b64", ""))
    if not rows:
        return {"passed": False, "score": 10, "feedback": "Output file exists but could not be parsed as valid CSV."}

    # 4. Verify Content
    score = 10 # Base score for creating file
    feedback_lines = []
    
    # Ground Truth Mapping
    ground_truth = task_info.get('metadata', {}).get('ground_truth', {})
    
    # Map input rows to ground truth based on chemical name similarity
    matched_chemicals = 0
    correct_fp_count = 0
    correct_hazard_count = 0
    correct_code_count = 0
    
    total_chemicals = len(ground_truth)
    
    for chem_name, truth in ground_truth.items():
        # Find matching row
        row = next((r for r in rows if chem_name.lower() in r.get('chemical name', '').lower()), None)
        
        if not row:
            feedback_lines.append(f"Missing chemical: {chem_name}")
            continue
            
        matched_chemicals += 1
        chem_score = 0
        
        # A. Check Flash Point
        fp_str = row.get('flash point (f)', '0').replace('°F', '').strip()
        # Handle "None" or non-numeric for non-flammables
        try:
            # Extract first number found
            import re
            nums = re.findall(r"[-+]?\d*\.\d+|\d+", fp_str)
            fp_val = float(nums[0]) if nums else None
        except:
            fp_val = None

        fp_correct = False
        if truth.get('fp_check') == 'none':
            # Expecting non-flammable indication
            # Accept if val is missing, or user wrote "None", "N/A", or > 2000
            if fp_val is None or fp_val > 500 or "none" in fp_str.lower() or "n/a" in fp_str.lower():
                fp_correct = True
        else:
            # Numeric check
            if fp_val is not None:
                if truth['fp_min'] <= fp_val <= truth['fp_max']:
                    fp_correct = True
        
        if fp_correct:
            correct_fp_count += 1
        
        # B. Check Hazards (Corrosive / Water Reactive)
        # Loose checking for "Yes"/"No"
        corr_input = row.get('corrosive?', '').lower()
        wr_input = row.get('water reactive?', '').lower()
        
        is_corr = 'yes' in corr_input or 'true' in corr_input
        is_wr = 'yes' in wr_input or 'true' in wr_input
        
        hazards_ok = (is_corr == truth['corrosive']) and (is_wr == truth['water_reactive'])
        if hazards_ok:
            correct_hazard_count += 1
            
        # C. Check Codes
        user_codes = normalize_codes(row.get('rcra codes', ''))
        truth_codes = set(truth['codes'])
        
        # Special case: Allow empty set if truth is empty
        if not truth_codes and not user_codes:
            code_correct = True
        else:
            code_correct = (user_codes == truth_codes)
            
        if code_correct:
            correct_code_count += 1
        else:
            feedback_lines.append(f"{chem_name}: Expected {truth_codes}, got {user_codes}")

    # 5. Calculate Score
    # Scoring Breakdown (Total 100):
    # - File exists & valid: 10 (Already added)
    # - Found all chemicals: 15 (3 pts each)
    # - Flash Points correct: 25 (5 pts each)
    # - Hazards correct: 25 (5 pts each)
    # - Codes correct: 25 (5 pts each)
    
    score += (matched_chemicals * 3)
    score += (correct_fp_count * 5)
    score += (correct_hazard_count * 5)
    score += (correct_code_count * 5)
    
    # Cap score at 100
    score = min(100, score)
    
    feedback = f"Processed {matched_chemicals}/{total_chemicals} chemicals. "
    if feedback_lines:
        feedback += "Errors: " + "; ".join(feedback_lines[:3])
        if len(feedback_lines) > 3:
            feedback += "..."
    else:
        feedback += "All Classifications Correct."

    passed = (score >= 80)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }