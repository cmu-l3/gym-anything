#!/usr/bin/env python3
"""
Verifier for Temporal Travel Anomaly task.

Verifies:
1. Database State: Agent identified true positives (set Suspicious=true).
2. Database State: Agent avoided false positives (didn't flag innocents).
3. File Output: Agent produced a JSON report matching ground truth.
4. Schema: Agent ensured the 'Suspicious' property exists.
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_temporal_travel_anomaly(traj, env_info, task_info):
    """
    Verify the temporal anomaly detection task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        
        # Also try to copy the agent's output file if it exists, to parse it locally
        # (Though export_result.sh checks for it, we want to parse the content safely here)
        agent_output_content = []
        if result.get("output_file_exists"):
            temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
            try:
                copy_from_env(result["output_file_path"], temp_output.name)
                with open(temp_output.name, 'r') as f_out:
                    agent_output_content = json.load(f_out)
            except Exception as e:
                logger.warning(f"Could not read agent output file content: {e}")
            finally:
                if os.path.exists(temp_output.name):
                    os.unlink(temp_output.name)

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification failed to read results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Data from result
    ground_truth = set(result.get("ground_truth_emails", []))
    db_flagged = set(result.get("db_flagged_emails", []))
    db_prop_exists = result.get("db_property_exists", False)
    
    # Process Agent Output File Content
    # Ensure it's a list of strings
    if isinstance(agent_output_content, list):
        file_flagged = set([str(e) for e in agent_output_content])
    else:
        file_flagged = set()

    score = 0
    feedback_parts = []
    
    # CRITERION 1: Database Schema (10 pts)
    if db_prop_exists:
        score += 10
        feedback_parts.append("Schema property 'Suspicious' confirmed.")
    else:
        feedback_parts.append("Schema property 'Suspicious' missing.")

    # CRITERION 2: Database State Accuracy (50 pts)
    # TP: Flagged in DB and in Ground Truth
    # FP: Flagged in DB but NOT in Ground Truth
    db_tp = db_flagged.intersection(ground_truth)
    db_fp = db_flagged.difference(ground_truth)
    
    if len(ground_truth) > 0:
        # Precision points
        if len(db_fp) == 0:
            score += 20
            feedback_parts.append("No false positives in database.")
        else:
            feedback_parts.append(f"Found {len(db_fp)} false positives in database.")
            
        # Recall points
        if len(db_tp) == len(ground_truth):
            score += 30
            feedback_parts.append(f"Correctly flagged all {len(ground_truth)} anomalies in database.")
        elif len(db_tp) > 0:
            partial = int(30 * (len(db_tp) / len(ground_truth)))
            score += partial
            feedback_parts.append(f"Flagged {len(db_tp)}/{len(ground_truth)} anomalies in database.")
        else:
            feedback_parts.append("No correct anomalies flagged in database.")
    
    # CRITERION 3: File Output Accuracy (40 pts)
    # Check if file existed and was created during task
    if result.get("output_file_exists") and result.get("output_file_created_during_task"):
        file_tp = file_flagged.intersection(ground_truth)
        file_fp = file_flagged.difference(ground_truth)
        
        # Accuracy of file content
        if len(file_fp) == 0 and len(file_tp) == len(ground_truth):
            score += 40
            feedback_parts.append("Report file is perfect.")
        elif len(file_tp) > 0:
            # Partial credit for file
            partial_file = int(30 * (len(file_tp) / len(ground_truth)))
            if len(file_fp) > 0:
                partial_file = max(0, partial_file - 10) # Penalty for noise
            score += partial_file
            feedback_parts.append(f"Report file contains {len(file_tp)} correct entries with errors.")
        else:
            score += 5 # Pity points for creating a valid JSON file
            feedback_parts.append("Report file created but content incorrect.")
    elif result.get("output_file_exists"):
        feedback_parts.append("Report file exists but was not modified during task.")
    else:
        feedback_parts.append("Report file not found.")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }