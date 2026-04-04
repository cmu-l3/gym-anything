#!/usr/bin/env python3
"""
Verifier for derive_reach_storage_curve task.

Verifies:
1. Output CSV existence and format.
2. Data validity (monotonicity).
3. Accuracy against ground truth (generated from reference implementation).
4. Evidence of work (script creation).
"""

import json
import os
import tempfile
import csv
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def read_csv_to_dict(filepath):
    """Read CSV into a dictionary {elevation: volume}."""
    data = {}
    try:
        with open(filepath, 'r') as f:
            reader = csv.reader(f)
            header = next(reader, None) # Skip header
            for row in reader:
                if len(row) < 2: continue
                try:
                    elev = int(float(row[0]))
                    vol = float(row[1])
                    data[elev] = vol
                except ValueError:
                    continue
    except Exception as e:
        logger.error(f"Error reading CSV {filepath}: {e}")
    return data

def verify_derive_reach_storage_curve(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_tolerance = metadata.get('tolerance_percent', 5.0)

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)

    output_exists = result.get('output_exists', False)
    file_created_during = result.get('file_created_during_task', False)
    script_created = result.get('script_created', False)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output CSV not found."}

    score += 10 # File exists
    if file_created_during:
        score += 10
    else:
        feedback_parts.append("Warning: Output file timestamp suspiciously old.")

    if script_created:
        score += 10
    else:
        feedback_parts.append("No Python script detected (did you write code?).")

    # 2. Retrieve CSVs
    agent_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    gt_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    
    try:
        copy_from_env(result.get('output_path'), agent_csv.name)
        copy_from_env(result.get('ground_truth_path'), gt_csv.name)
        
        agent_data = read_csv_to_dict(agent_csv.name)
        gt_data = read_csv_to_dict(gt_csv.name)
        
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read CSV data: {e}"}
    finally:
        if os.path.exists(agent_csv.name): os.unlink(agent_csv.name)
        if os.path.exists(gt_csv.name): os.unlink(gt_csv.name)

    # 3. Validation Logic
    
    # Check Range (925-955)
    missing_elevs = [e for e in range(925, 956) if e not in agent_data]
    if not missing_elevs:
        score += 10
    else:
        feedback_parts.append(f"Missing data for elevations: {missing_elevs[:3]}...")

    # Check Monotonicity
    elevs = sorted(agent_data.keys())
    vols = [agent_data[e] for e in elevs]
    is_monotonic = all(x <= y for x, y in zip(vols, vols[1:]))
    if is_monotonic and len(vols) > 5:
        score += 20
    elif len(vols) <= 5:
        feedback_parts.append("Insufficient data points for monotonicity check.")
    else:
        feedback_parts.append("Volume curve is not monotonic (physically impossible).")

    # Check Accuracy
    passed_accuracy = False
    matches = 0
    total_checks = 0
    
    check_elevs = [930, 940, 950]
    
    if not gt_data:
         feedback_parts.append("Verifier error: Ground truth generation failed.")
    else:
        for e in check_elevs:
            if e in agent_data and e in gt_data:
                total_checks += 1
                agent_val = agent_data[e]
                gt_val = gt_data[e]
                
                # Avoid division by zero
                if gt_val == 0:
                    diff = abs(agent_val - gt_val)
                    if diff < 0.1: # absolute tolerance for zero
                        matches += 1
                else:
                    percent_diff = abs((agent_val - gt_val) / gt_val) * 100
                    if percent_diff <= expected_tolerance:
                        matches += 1
                    else:
                        feedback_parts.append(f"Elev {e}: Expected ~{gt_val:.2f}, got {agent_val:.2f} ({percent_diff:.1f}% diff)")
        
        # Award points for accuracy (20 pts per checkpoint)
        if total_checks > 0:
            score += (matches / 3) * 60 # Max 60 points for accuracy
    
    passed = score >= 70 and matches >= 2
    
    if passed:
        feedback_parts.append("Excellent work! Storage curve derived accurately.")
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }