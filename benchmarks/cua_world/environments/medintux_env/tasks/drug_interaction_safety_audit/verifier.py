#!/usr/bin/env python3
"""
Verifier for Drug Interaction Safety Audit.

Checks if the agent correctly identified patients with both drugs in their history.
Metrics:
- Sensitivity (Recall): Did they find all at-risk patients?
- Precision: Did they avoid false positives (patients with only one drug)?
"""

import json
import csv
import os
import logging
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_name(name):
    """Normalize 'Lastname Firstname' string."""
    if not name:
        return ""
    # Remove extra spaces, lowercase
    return " ".join(name.strip().lower().split())

def load_csv_guids(filepath):
    """Load GUIDs and Names from CSV. Returns set of GUIDs."""
    guids = set()
    names = set()
    try:
        with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
            reader = csv.DictReader(f)
            # Normalize headers
            reader.fieldnames = [h.strip() for h in reader.fieldnames]
            
            # Check required columns
            if 'GUID' not in reader.fieldnames:
                logger.warning(f"Column GUID missing in {filepath}. Available: {reader.fieldnames}")
                return None, None
            
            for row in reader:
                if row['GUID'].strip():
                    guids.add(row['GUID'].strip().upper())
                if 'PatientName' in row and row['PatientName'].strip():
                    names.add(normalize_name(row['PatientName']))
    except Exception as e:
        logger.error(f"Error reading CSV {filepath}: {e}")
        return None, None
    return guids, names

def verify_drug_interaction_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Paths
    gt_remote = "/tmp/ground_truth.csv"
    agent_remote = "/tmp/agent_output.csv"
    meta_remote = "/tmp/task_result.json"

    # Local temp files
    import tempfile
    gt_local = tempfile.mktemp()
    agent_local = tempfile.mktemp()
    meta_local = tempfile.mktemp()

    try:
        # Copy files
        try:
            copy_from_env(gt_remote, gt_local)
            copy_from_env(agent_remote, agent_local)
            copy_from_env(meta_remote, meta_local)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result files: {e}"}

        # Read Metadata
        with open(meta_local, 'r') as f:
            meta = json.load(f)

        if not meta.get('output_exists', False):
            return {"passed": False, "score": 0, "feedback": "Output CSV file not found at ~/Documents/interaction_alert_list.csv"}
        
        if not meta.get('created_during_task', False):
            # Soft fail or penalty? Task requires creating it.
            # Assuming strictly enforced:
            pass # We'll penalize in scoring if needed, but existence is primary step.

        # Load Data
        gt_guids, gt_names = load_csv_guids(gt_local)
        agent_guids, agent_names = load_csv_guids(agent_local)

        if agent_guids is None:
            return {"passed": False, "score": 10, "feedback": "Output CSV format incorrect (Missing 'GUID' column or unreadable)."}

        # Calculate Metrics using GUIDs (primary key)
        # If agent used Names only (no GUIDs populated), we might fallback to Name matching, 
        # but the task explicitly requested GUIDs.
        
        # Intersection
        true_positives = gt_guids.intersection(agent_guids)
        false_positives = agent_guids - gt_guids
        false_negatives = gt_guids - agent_guids

        tp_count = len(true_positives)
        fp_count = len(false_positives)
        fn_count = len(false_negatives)
        gt_total = len(gt_guids)

        # Scores
        # 1. File existence & Structure (already checked partially) -> 20 pts
        score_base = 20

        # 2. Recall (Sensitivity) -> 40 pts max
        # Found / Total Existing
        if gt_total > 0:
            recall = tp_count / gt_total
            score_recall = recall * 40
        else:
            score_recall = 40 # Should not happen

        # 3. Precision -> 40 pts max
        # Found Correct / Total Found
        if len(agent_guids) > 0:
            precision = tp_count / len(agent_guids)
            score_precision = precision * 40
        else:
            score_precision = 0

        total_score = score_base + score_recall + score_precision

        # Feedback construction
        feedback = f"Found {tp_count}/{gt_total} at-risk patients."
        if fp_count > 0:
            feedback += f" Included {fp_count} incorrect patients (False Positives)."
        if fn_count > 0:
            feedback += f" Missed {fn_count} patients (False Negatives)."
            
        passed = (recall >= 0.99 and precision >= 0.8) # Allow slight error? No, exact query should be exact.
        # Actually, let's allow 100% recall and high precision.
        
        # Strict pass: Must find all targets.
        passed = (fn_count == 0) and (total_score >= 80)

        return {
            "passed": passed,
            "score": int(total_score),
            "feedback": feedback
        }

    except Exception as e:
        logger.exception("Verification failed")
        return {"passed": False, "score": 0, "feedback": f"Verification logic error: {e}"}
    finally:
        # Cleanup
        for f in [gt_local, agent_local, meta_local]:
            if os.path.exists(f):
                os.unlink(f)