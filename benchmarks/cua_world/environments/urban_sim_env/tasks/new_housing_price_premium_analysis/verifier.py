#!/usr/bin/env python3
"""
Verifier for new_housing_price_premium_analysis task.

Checks:
1. Notebook execution and structure (10 pts)
2. CSV File Structure & File existence (10 pts)
3. Data Filtering Constraints & Edge Cases (20 pts)
4. Math & Internal Consistency Validation (20 pts)
5. Ground Truth Accuracy Verification (20 pts)
6. Visualization Existence & Timestamps (20 pts)
"""

import json
import tempfile
import os
import csv
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_price_premium(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_csv_path = metadata.get('expected_csv_path', '/home/ga/urbansim_projects/output/zone_premium_analysis.csv')
    min_new = metadata.get('min_new_units', 20)
    min_existing = metadata.get('min_existing_units', 50)
    
    score = 0
    feedback = []

    # ---------------------------------------------------------
    # PART 1: Read JSON Task Result Exported from Container
    # ---------------------------------------------------------
    result = None
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        feedback.append(f"Could not read task export result: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if result is None:
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Notebook Evaluation (10 points)
    nb_score = 0
    if result.get('notebook_exists') and result.get('notebook_modified'):
        nb_score += 4
        nb_a = result.get('notebook_analysis', {})
        if nb_a.get('num_executed_cells', 0) >= 3:
            nb_score += 3
        if nb_a.get('has_group_merge'):
            nb_score += 3
    score += nb_score
    feedback.append(f"Notebook Setup: {nb_score}/10")

    # Visualizations Evaluation (20 points)
    vis_score = 0
    if result.get('scatter_exists') and result.get('scatter_created') and result.get('scatter_size_kb', 0) > 10:
        vis_score += 10
    if result.get('bar_exists') and result.get('bar_created') and result.get('bar_size_kb', 0) > 10:
        vis_score += 10
    score += vis_score
    feedback.append(f"Visualizations: {vis_score}/20")

    if not result.get('csv_exists') or not result.get('csv_created'):
        feedback.append("CSV output not found or not created during task.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # ---------------------------------------------------------
    # PART 2: CSV Data Extraction and Validation
    # ---------------------------------------------------------
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    csv_rows = []
    headers = []
    try:
        copy_from_env(expected_csv_path, temp_csv.name)
        with open(temp_csv.name, 'r', encoding='utf-8') as f:
            reader = csv.reader(f)
            headers = [h.strip().lower() for h in next(reader, [])]
            for row in reader:
                if any(row):  # Skip empty lines
                    csv_rows.append(row)
    except Exception as e:
        feedback.append(f"Failed reading CSV: {e}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # Structure check (10 points)
    required_cols = ['zone_id', 'new_units', 'existing_units', 'median_price_new', 'median_price_existing', 'price_premium_ratio']
    has_all_cols = all(any(c in h for h in headers) for c in required_cols)
    
    if has_all_cols and len(csv_rows) > 0:
        score += 10
        feedback.append("CSV Structure: 10/10")
    else:
        feedback.append("CSV Structure failed: Missing columns or empty")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # Map indexes dynamically
    idx = {col: next((i for i, h in enumerate(headers) if col in h), -1) for col in required_cols}

    # Iterate over rows to validate math and constraints
    math_correct_count = 0
    constraints_met_count = 0
    total_valid_rows = len(csv_rows)
    agent_premium_sum = 0.0

    for row in csv_rows:
        try:
            n_units = float(row[idx['new_units']])
            e_units = float(row[idx['existing_units']])
            p_new = float(row[idx['median_price_new']])
            p_ext = float(row[idx['median_price_existing']])
            p_ratio = float(row[idx['price_premium_ratio']])
            
            # Constraint check
            if n_units >= min_new and e_units >= min_existing:
                constraints_met_count += 1
                
            # Math check (Price Premium Ratio = New / Existing)
            expected_ratio = p_new / p_ext if p_ext > 0 else 0
            if abs(expected_ratio - p_ratio) < 0.05:
                math_correct_count += 1
                
            agent_premium_sum += p_ratio
        except (ValueError, IndexError):
            pass

    # Constraint Evaluation (20 points)
    constraint_score = 0
    if total_valid_rows > 0:
        if constraints_met_count == total_valid_rows:
            constraint_score = 20
        else:
            constraint_score = int((constraints_met_count / total_valid_rows) * 20)
    score += constraint_score
    feedback.append(f"Filter Constraints: {constraint_score}/20")

    # Math Evaluation (20 points)
    math_score = 0
    if total_valid_rows > 0:
        if math_correct_count == total_valid_rows:
            math_score = 20
        else:
            math_score = int((math_correct_count / total_valid_rows) * 20)
    score += math_score
    feedback.append(f"Math Consistency: {math_score}/20")

    # ---------------------------------------------------------
    # PART 3: Ground Truth Accuracy (20 points)
    # ---------------------------------------------------------
    gt_score = 0
    gt_zones = result.get('gt_valid_zones', 0)
    gt_mean = result.get('gt_mean_premium', 0)
    
    agent_mean = (agent_premium_sum / total_valid_rows) if total_valid_rows > 0 else 0.0
    
    logger.info(f"Agent Valid Zones: {total_valid_rows}, GT Valid Zones: {gt_zones}")
    logger.info(f"Agent Mean Premium: {agent_mean:.4f}, GT Mean Premium: {gt_mean:.4f}")

    if gt_zones > 0:
        # Check zone count accuracy (±2 tolerance for slight NA handling differences)
        if abs(total_valid_rows - gt_zones) <= 2:
            gt_score += 10
        elif abs(total_valid_rows - gt_zones) <= 10:
            gt_score += 5
            
        # Check ratio accuracy (±5% tolerance on the mean ratio)
        if abs(agent_mean - gt_mean) <= (0.05 * gt_mean):
            gt_score += 10
        elif abs(agent_mean - gt_mean) <= (0.15 * gt_mean):
            gt_score += 5
            
    score += gt_score
    feedback.append(f"Ground Truth Accuracy: {gt_score}/20")

    # Determine passing status
    passed = score >= 70 and constraint_score == 20 and math_score == 20

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }