#!/usr/bin/env python3
"""
Verifier for identify_lost_followup_cohort task.

Verifies:
1. 'CallList.csv' exists and was created during the task.
2. The list contains the correct 'Lost to Follow-up' participants (Recall).
3. The list does NOT contain participants who returned (Precision).
4. The CSV has the required columns.
"""

import json
import os
import csv
import logging
import tempfile
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_lost_followup(traj, env_info, task_info):
    """
    Verify the agent correctly identified lost-to-follow-up participants.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', r'C:\Users\Docker\Documents\Output\CallList.csv')
    ground_truth_path = metadata.get('ground_truth_path', r'C:\Users\Docker\Documents\Data\ground_truth_ids.txt')

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Windows\\Temp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task status: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Check File Existence (10 pts)
    if not result_data.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file CallList.csv not found."}
    score += 10
    feedback_parts.append("Output file exists")

    # Check Creation Time (10 pts)
    if result_data.get('file_created_during_task', False):
        score += 10
    else:
        feedback_parts.append("Warning: File timestamp indicates it wasn't created during this session")

    # Check Project Creation (10 pts)
    if result_data.get('project_created', False):
        score += 10
        feedback_parts.append("Project file created")
    else:
        feedback_parts.append("Warning: CohortRetention.prj not found")

    # 2. Retrieve Output File and Ground Truth
    temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        copy_from_env(expected_output_path, temp_output.name)
        copy_from_env(ground_truth_path, temp_gt.name)
        
        # Load Ground Truth
        with open(temp_gt.name, 'r') as f:
            # Clean formatting (UTF-16 BOMs from PowerShell sometimes occur)
            content = f.read().replace('\x00', '').strip() 
            gt_ids = set([line.strip() for line in content.splitlines() if line.strip()])
        
        # Load Agent Output
        agent_ids = set()
        has_required_cols = False
        
        with open(temp_output.name, 'r', encoding='utf-8-sig', errors='replace') as f:
            # Handle potential encoding issues from Epi Info export
            reader = csv.DictReader(f)
            if reader.fieldnames:
                # Normalize field names (case insensitive)
                field_map = {name.lower(): name for name in reader.fieldnames}
                required = ['participantid', 'firstname', 'lastname', 'phone']
                
                # Check Columns (20 pts)
                missing_cols = [col for col in required if col not in field_map]
                if not missing_cols:
                    score += 20
                    has_required_cols = True
                    feedback_parts.append("Correct columns found")
                else:
                    feedback_parts.append(f"Missing columns: {missing_cols}")

                # Extract IDs
                id_col = field_map.get('participantid')
                if id_col:
                    for row in reader:
                        val = row.get(id_col, '').strip()
                        if val:
                            agent_ids.add(val)
        
        # 3. Calculate Precision and Recall
        if not gt_ids:
            feedback_parts.append("Error: Ground truth is empty")
            passed = False
        else:
            # Recall: Found the lost patients (30 pts)
            true_positives = agent_ids.intersection(gt_ids)
            recall = len(true_positives) / len(gt_ids)
            recall_score = int(recall * 30)
            score += recall_score
            
            # Precision: Didn't include returned patients (20 pts)
            # False positives are IDs in agent output that are NOT in ground truth
            # Note: We assume agent_ids only contains valid IDs. If agent exports garbage, precision drops.
            if len(agent_ids) > 0:
                precision = len(true_positives) / len(agent_ids)
                precision_score = int(precision * 20)
                score += precision_score
            else:
                precision = 0
                precision_score = 0
            
            feedback_parts.append(f"Recall: {recall:.1%} ({len(true_positives)}/{len(gt_ids)})")
            feedback_parts.append(f"Precision: {precision:.1%} ({len(true_positives)}/{len(agent_ids)})")

    except Exception as e:
        feedback_parts.append(f"Verification error: {str(e)}")
        # Partial score for file existence might remain
    finally:
        if os.path.exists(temp_output.name):
            os.unlink(temp_output.name)
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }