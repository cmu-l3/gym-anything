#!/usr/bin/env python3
"""
Verifier for generate_mitre_coverage_report task.

Verifies:
1. File existence and valid JSON structure.
2. Correct schema (metadata, techniques list).
3. Data accuracy by comparing against ground truth spot checks from live API.
4. Internal consistency of totals.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mitre_report(traj, env_info, task_info):
    """
    Verify the generated MITRE coverage report.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    max_score = 100
    feedback = []
    
    # --- Check 1: File Existence & Basic Properties (10 pts) ---
    if not result_data.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Report file not found at expected path."}
    
    if not result_data.get('file_created_during_task'):
        feedback.append("Warning: File timestamp suggests it wasn't created during this task session.")
        # We don't fail immediately but penalty could be applied if strict
    
    score += 10
    feedback.append("Report file exists.")

    # --- Check 2: JSON Structure & Schema (20 pts) ---
    user_report = result_data.get('user_report_content', {})
    
    # Check top level keys
    if 'report_metadata' in user_report and 'techniques' in user_report:
        score += 10
        feedback.append("Valid JSON structure (metadata/techniques present).")
    else:
        return {"passed": False, "score": score, "feedback": "Invalid JSON structure. Missing 'report_metadata' or 'techniques'."}

    # Check metadata fields
    metadata = user_report.get('report_metadata', {})
    if all(k in metadata for k in ['generated_by', 'total_techniques_covered', 'total_rules_with_mitre']):
        score += 5
    else:
        feedback.append("Missing required metadata fields.")

    # Check techniques array
    techniques = user_report.get('techniques', [])
    if isinstance(techniques, list) and len(techniques) > 0:
        score += 5
    else:
        return {"passed": False, "score": score, "feedback": "Techniques list is empty or invalid."}

    # --- Check 3: Data Quality & Format (30 pts) ---
    
    # Format of Technique IDs (Txxxx)
    invalid_ids = [t.get('technique_id') for t in techniques if not re.match(r'^T\d{4}(\.\d{3})?$', str(t.get('technique_id', '')))]
    if not invalid_ids:
        score += 10
    else:
        feedback.append(f"Found invalid technique IDs: {invalid_ids[:3]}...")

    # Sort order
    ids = [t.get('technique_id', '') for t in techniques]
    if ids == sorted(ids):
        score += 5
    else:
        feedback.append("Techniques list is not sorted by ID.")

    # Tactics populated
    tactics_present = sum(1 for t in techniques if t.get('tactics') and len(t['tactics']) > 0)
    if tactics_present / len(techniques) > 0.8:
        score += 10
        feedback.append("Tactics data populated for >80% of techniques.")
    else:
        feedback.append("Tactics data missing for many techniques.")
    
    # Non-zero counts
    zero_counts = sum(1 for t in techniques if t.get('rule_count', 0) == 0)
    if zero_counts == 0:
        score += 5
    else:
        feedback.append(f"Found {zero_counts} techniques with 0 rule count (should filter these out).")

    # --- Check 4: Accuracy against Ground Truth (40 pts) ---
    ground_truth = result_data.get('ground_truth', {})
    
    # Spot checks
    check_techniques = {
        'T1110': ground_truth.get('t1110_count', 0),
        'T1053': ground_truth.get('t1053_count', 0),
        'T1059': ground_truth.get('t1059_count', 0)
    }
    
    matched_spots = 0
    for tech_id, expected_count in check_techniques.items():
        # Find in user report
        user_tech = next((t for t in techniques if t.get('technique_id') == tech_id), None)
        
        if user_tech:
            user_count = user_tech.get('rule_count', 0)
            # Allow slight mismatch if API results fluctuate or different query logic used
            # e.g. some queries include parent/child relationships differently
            if expected_count > 0:
                diff = abs(user_count - expected_count)
                percent_diff = diff / expected_count
                if percent_diff <= 0.15 or diff <= 2: # 15% tolerance or within 2 rules
                    matched_spots += 1
                else:
                    feedback.append(f"Count mismatch for {tech_id}: Agent={user_count}, Truth={expected_count}")
            else:
                # If ground truth is 0, user should also be 0 or not present
                if user_count == 0:
                    matched_spots += 1
        elif expected_count == 0:
            matched_spots += 1 # Correctly omitted
        else:
            feedback.append(f"Missing technique {tech_id} in report (Expected ~{expected_count} rules)")

    # Score based on matches
    if matched_spots >= 3:
        score += 20
        feedback.append("Spot checks passed for known techniques.")
    elif matched_spots >= 1:
        score += 10
        feedback.append("Partial pass on spot checks.")
    
    # Total coverage reasonable range (Wazuh 4.x usually has 100-300 covered techniques)
    total_covered = metadata.get('total_techniques_covered', 0)
    if 50 <= total_covered <= 500:
        score += 10
    else:
        feedback.append(f"Total techniques covered ({total_covered}) seems outside expected range (50-500).")

    # Internal consistency
    calculated_total = sum(t.get('rule_count', 0) for t in techniques)
    reported_total = metadata.get('total_rules_with_mitre', 0)
    
    if calculated_total == reported_total:
        score += 10
    else:
        feedback.append(f"Internal inconsistency: Metadata says {reported_total} rules, sum of techniques is {calculated_total}.")

    # --- Final Result ---
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }