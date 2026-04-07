#!/usr/bin/env python3
"""Verifier for lambda_ladder_double_digest task.

Scoring breakdown (100 points total):
  FASTA Export Exists & valid timestamp:     15
  Correct Fragment Count (13):               25
  Correct Fragment Sizes extracted:          25
  Size Report (TXT) Exists:                  10
  Report Content Accuracy:                   15
  Report Sort Order (Descending):            10
                             TOTAL =        100
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_lambda_ladder_double_digest(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected metadata
    metadata = task_info.get('metadata', {})
    expected_count = metadata.get('expected_fragment_count', 13)
    expected_sizes = metadata.get('expected_sizes', [21226, 5148, 4973, 4268, 3530, 2027, 1904, 1584, 1375, 947, 831, 564, 125])
    tolerance = metadata.get('size_tolerance_bp', 5)

    # Read exported JSON
    result = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/lambda_digest_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to read task results. Did the agent output the required files?"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # Anti-gaming variables
    fasta_exists = result.get('fasta_exists', False)
    fasta_created_during_task = result.get('fasta_created_during_task', False)
    txt_exists = result.get('txt_exists', False)
    txt_created_during_task = result.get('txt_created_during_task', False)
    extracted_lengths = result.get('extracted_lengths', [])
    reported_sizes = result.get('reported_sizes', [])
    
    # --- Criterion 1: FASTA Exists & Created During Task (15 pts) ---
    if fasta_exists and fasta_created_during_task:
        score += 15
        feedback_parts.append("FASTA file correctly exported (+15)")
    elif fasta_exists:
        score += 5
        feedback_parts.append("FASTA file exists but was not created during task (+5)")
    else:
        feedback_parts.append("FASTA file MISSING (0)")

    # --- Criterion 2: Correct Fragment Count (25 pts) ---
    actual_count = result.get('fasta_sequence_count', 0)
    if actual_count == expected_count:
        score += 25
        feedback_parts.append(f"Correct fragment count: {actual_count} (+25)")
    elif actual_count > 0:
        # Partial credit if they extracted something, but missed some cut sites
        prop = max(0, 25 - (abs(actual_count - expected_count) * 5))
        score += prop
        feedback_parts.append(f"Incorrect fragment count: {actual_count} (expected {expected_count}) (+{prop})")
    else:
        feedback_parts.append("No sequences found in FASTA (0)")

    # --- Criterion 3: Correct Fragment Sizes (25 pts) ---
    # We compare extracted_lengths vs expected_sizes (both are sorted descending)
    sizes_match_score = 0
    if actual_count > 0:
        matches = 0
        used_indices = set()
        
        for expected in expected_sizes:
            best_match_idx = -1
            best_diff = 999999
            for i, actual in enumerate(extracted_lengths):
                if i in used_indices:
                    continue
                diff = abs(expected - actual)
                if diff <= tolerance and diff < best_diff:
                    best_diff = diff
                    best_match_idx = i
            
            if best_match_idx != -1:
                matches += 1
                used_indices.add(best_match_idx)
                
        # Proportional scoring based on matches
        sizes_match_score = int((matches / expected_count) * 25)
        score += sizes_match_score
        feedback_parts.append(f"Fragment sizes matched: {matches}/{expected_count} (+{sizes_match_score})")
    else:
        feedback_parts.append("No sequences to evaluate sizes (0)")

    # --- Criterion 4: Size Report Exists (10 pts) ---
    if txt_exists and txt_created_during_task:
        score += 10
        feedback_parts.append("Size report created (+10)")
    elif txt_exists:
        score += 3
        feedback_parts.append("Size report exists but wasn't created during task (+3)")
    else:
        feedback_parts.append("Size report MISSING (0)")

    # --- Criterion 5: Report Content Accuracy (15 pts) ---
    # Check if the numbers reported reflect the expected double digest
    report_acc_score = 0
    if len(reported_sizes) > 0:
        matches = 0
        for expected in expected_sizes:
            for rep in reported_sizes:
                if abs(expected - rep) <= tolerance:
                    matches += 1
                    break
                    
        report_acc_score = int((matches / expected_count) * 15)
        score += report_acc_score
        feedback_parts.append(f"Report accuracy: {matches}/{expected_count} expected sizes found (+{report_acc_score})")
    else:
        feedback_parts.append("No numerical sizes found in report (0)")

    # --- Criterion 6: Report Sort Order (10 pts) ---
    if len(reported_sizes) >= 3:
        # Check if they are strictly descending (allowing for occasional duplicate overhang issues)
        is_descending = True
        for i in range(len(reported_sizes) - 1):
            if reported_sizes[i] < reported_sizes[i+1]:
                is_descending = False
                break
                
        if is_descending:
            score += 10
            feedback_parts.append("Report sizes are sorted descending (+10)")
        else:
            feedback_parts.append("Report sizes are NOT sorted descending (0)")
    else:
        feedback_parts.append("Insufficient data in report to verify sorting (0)")

    # Final pass/fail logic
    # Must get at least 80 points, specifically needing accurate count and sizes
    passed = score >= 80 and (sizes_match_score >= 20) and fasta_exists

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }