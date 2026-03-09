#!/usr/bin/env python3
"""
Verifier for Forensic Chemical Property Matching Task.
Checks if the agent correctly identified 5 unknown bottles based on CAMEO Chemicals data.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_forensic_match(traj, env_info, task_info):
    """
    Verifies the chemical identification report.
    
    Scoring Criteria:
    - File exists and created during task (10 pts)
    - Correct Match for Bottle A (10 pts)
    - Correct Match for Bottle B (10 pts)
    - Correct Match for Bottle C (10 pts)
    - Correct Match for Bottle D (10 pts)
    - Correct Match for Bottle E (10 pts)
    - Evidence of data lookup (Reference BP/FP included and reasonably accurate) (40 pts)
    
    Total: 100 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_matches = metadata.get('ground_truth_matches', {})
    ref_props = metadata.get('reference_properties', {})
    
    score = 0
    feedback_parts = []
    
    # 1. Get Export Result (File Meta-data)
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            export_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load export result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    if not export_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Report file not found"}
        
    if not export_result.get('file_created_during_task', False):
        feedback_parts.append("Warning: File not created during task time window")
        # We penalize but don't fail immediately, in case of clock skew, but strictly it's an anti-gaming check.
        # For this implementation, we'll allow it but deduct points.
        score -= 10
    else:
        score += 10
        feedback_parts.append("File created successfully")

    # 2. Parse the Report Content
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/home/ga/Documents/chemical_identification_report.txt", temp_report.name)
        with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
            report_content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read report content: {e}"}
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)

    # Normalize content for matching
    report_lines = report_content.splitlines()
    
    matches_found = 0
    data_evidence_score = 0
    
    # Logic to check each bottle
    # We look for lines starting with "Bottle X:"
    bottle_regex = re.compile(r"Bottle\s+([A-E])\s*[:\-]\s*([A-Za-z\s]+)", re.IGNORECASE)
    
    # We also look for numbers in the same line for evidence verification
    # Matches patterns like "82 C", "179 F", "82", etc.
    number_regex = re.compile(r"(-?\d+\.?\d*)")

    for line in report_lines:
        match = bottle_regex.search(line)
        if match:
            bottle_id = f"Bottle {match.group(1).upper()}"
            chem_name = match.group(2).strip()
            
            # Check correctness of chemical identification
            expected_chem = expected_matches.get(bottle_id)
            
            # Fuzzy match chemical name (contains expected name)
            if expected_chem and (expected_chem.lower() in chem_name.lower() or 
                                  ("THF" in chem_name.upper() and "Tetrahydrofuran" in expected_chem)):
                matches_found += 1
                score += 10 # 10 pts per correct bottle
                feedback_parts.append(f"Correct: {bottle_id} -> {chem_name}")
                
                # Check for evidence (Reference Values) in the same line
                # Extract all numbers from the line
                numbers_in_line = [float(x) for x in number_regex.findall(line)]
                
                # Get ground truth props
                # Handle THF alias
                lookup_name = "Tetrahydrofuran" if "THF" in chem_name.upper() else expected_chem
                props = ref_props.get(lookup_name, {})
                gt_bp = props.get('bp')
                gt_fp = props.get('fp')
                
                # Check if numbers in line match BP or FP (with tolerance)
                # Tolerance: +/- 5 degrees
                bp_found = any(abs(n - gt_bp) < 5 for n in numbers_in_line)
                fp_found = any(abs(n - gt_fp) < 5 for n in numbers_in_line)
                
                # Also check Fahrenheit matches just in case agent logged F
                gt_bp_f = (gt_bp * 9/5) + 32
                gt_fp_f = (gt_fp * 9/5) + 32
                bp_f_found = any(abs(n - gt_bp_f) < 10 for n in numbers_in_line)
                fp_f_found = any(abs(n - gt_fp_f) < 10 for n in numbers_in_line)
                
                if (bp_found or bp_f_found) and (fp_found or fp_f_found):
                    data_evidence_score += 8 # 8 pts per bottle for evidence
                elif (bp_found or bp_f_found) or (fp_found or fp_f_found):
                    data_evidence_score += 4 # Partial evidence
                
            else:
                feedback_parts.append(f"INCORRECT: {bottle_id} -> {chem_name} (Expected {expected_chem})")

    score += data_evidence_score
    if data_evidence_score > 0:
        feedback_parts.append(f"Data Evidence Score: {data_evidence_score}/40")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(100, max(0, score)),
        "feedback": " | ".join(feedback_parts)
    }