#!/usr/bin/env python3
"""
Verifier for chinook_resurrected_customer_analysis task.
Scoring Breakdown:
- Connection Created: 10 pts
- Output CSV Exists: 10 pts
- CSV Created During Task: 10 pts (Anti-gaming)
- Correct Columns: 15 pts
- Data Accuracy (Precision/Recall + Spend Value): 45 pts
- SQL Script Exists: 10 pts
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_key(key):
    return key.lower().replace(" ", "").replace("_", "")

def verify_resurrected_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    agent_rows = result_data.get('agent_data', [])
    gt_rows = result_data.get('ground_truth', [])
    meta = result_data.get('meta', {})

    score = 0
    feedback = []

    # 1. Connection Check (10 pts)
    if meta.get('connection_exists'):
        score += 10
        feedback.append("DBeaver 'Chinook' connection found.")
    else:
        feedback.append("DBeaver 'Chinook' connection NOT found.")

    # 2. File Existence & Timing (20 pts)
    if meta.get('csv_exists'):
        score += 10
        feedback.append("Output CSV exists.")
        if meta.get('csv_created_during'):
            score += 10
            feedback.append("Output CSV created during task.")
        else:
            feedback.append("Output CSV timestamp is stale (pre-task).")
    else:
        feedback.append("Output CSV NOT found.")
        # If no CSV, we can't score content
        return {
            "passed": False,
            "score": score,
            "feedback": "\n".join(feedback)
        }

    # 3. SQL Script Check (10 pts)
    if meta.get('sql_exists'):
        score += 10
        feedback.append("SQL script saved.")
    else:
        feedback.append("SQL script NOT found.")

    # 4. Column Structure Check (15 pts)
    # Required: CustomerId, FirstName, LastName, ReturnSpend2011
    required_cols = {'customerid', 'firstname', 'lastname', 'returnspend2011'}
    if agent_rows:
        # Normalize keys in first row to check
        agent_keys = {normalize_key(k) for k in agent_rows[0].keys()}
        missing = required_cols - agent_keys
        if not missing:
            score += 15
            feedback.append("CSV has all required columns.")
        else:
            score += 5 # Partial credit if file exists with data
            feedback.append(f"CSV missing columns: {missing}")
    else:
        feedback.append("CSV is empty.")

    # 5. Data Accuracy (45 pts)
    # We compare sets of CustomerIds and the specific Spend values
    
    # Build maps {CustomerId: Spend}
    # Handle variations in casing/formatting
    def get_id_spend(rows):
        data_map = {}
        for row in rows:
            # Find ID key
            id_key = next((k for k in row.keys() if 'customerid' in k.lower()), None)
            spend_key = next((k for k in row.keys() if 'spend' in k.lower()), None)
            
            if id_key and spend_key:
                try:
                    cust_id = str(row[id_key])
                    spend = float(row[spend_key])
                    data_map[cust_id] = spend
                except ValueError:
                    continue
        return data_map

    gt_map = get_id_spend(gt_rows)
    agent_map = get_id_spend(agent_rows)

    gt_ids = set(gt_map.keys())
    agent_ids = set(agent_map.keys())

    # Precision/Recall logic
    # Expected IDs (from setup): 1 and 5
    # False positives (from setup): 2, 3, 4
    
    true_positives = gt_ids.intersection(agent_ids)
    false_positives = agent_ids - gt_ids
    false_negatives = gt_ids - agent_ids

    # Scoring ID Match (30 pts)
    if len(gt_ids) > 0:
        recall = len(true_positives) / len(gt_ids)
        score += int(15 * recall)
        
        # Penalize false positives
        if len(agent_ids) > 0:
            precision = len(true_positives) / len(agent_ids)
            score += int(15 * precision)
        
        feedback.append(f"Customer Identification: Found {len(true_positives)}/{len(gt_ids)} correct. {len(false_positives)} false positives.")
    
    # Scoring Spend Accuracy (15 pts)
    # Only check spend for the True Positives
    spend_matches = 0
    if true_positives:
        for cid in true_positives:
            # Allow 1% tolerance
            gt_spend = gt_map[cid]
            agent_spend = agent_map[cid]
            if abs(gt_spend - agent_spend) < 0.1:
                spend_matches += 1
        
        spend_accuracy = spend_matches / len(true_positives)
        score += int(15 * spend_accuracy)
        feedback.append(f"Spend Calculation: {spend_matches}/{len(true_positives)} values correct.")
    
    final_passed = score >= 65 and len(true_positives) > 0 and len(false_positives) == 0

    return {
        "passed": final_passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }