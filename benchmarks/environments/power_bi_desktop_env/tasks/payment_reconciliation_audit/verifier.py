#!/usr/bin/env python3
"""
Verifier for Payment Reconciliation Audit task.

Scoring (100 points total):
1. Report Saved (10 pts)
2. CSV Exported (10 pts)
3. Reconciliation Logic / CSV Content (40 pts) - Checks if exported CSV matches missing IDs
4. Table Visual Present (10 pts)
5. Summary Bar Chart Present (15 pts)
6. KPI Card Present (15 pts)

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_payment_reconciliation_audit(traj, env_info, task_info):
    """
    Verifies that the agent correctly identified missing transactions and built the report.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON from the Windows environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        copy_from_env("C:/Users/Docker/Desktop/reconciliation_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig', errors='replace') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass

    score = 0
    feedback = []
    
    # 1. PBIX Existence (10 pts)
    if result.get('pbix_exists'):
        score += 10
        feedback.append("Report file saved.")
    else:
        feedback.append("Report file (Reconciliation_Audit.pbix) not found.")

    # 2. CSV Existence (10 pts)
    if result.get('csv_exists'):
        score += 10
        feedback.append("CSV export found.")
    else:
        feedback.append("CSV export (unsettled_list.csv) not found.")

    # 3. Reconciliation Logic (40 pts)
    # Compare exported CSV rows against ground truth missing IDs
    ground_truth_ids = set(result.get('ground_truth', {}).get('missing_ids', []))
    
    # Normalize CSV data (handle potential column name variations)
    csv_rows = result.get('csv_rows', [])
    exported_ids = set()
    
    for row in csv_rows:
        # Try finding the ID in various common column names
        for key, val in row.items():
            if 'id' in key.lower() or 'order' in key.lower():
                try:
                    exported_ids.add(int(val))
                except:
                    pass
    
    # Calculate F1-like score for intersection
    if not ground_truth_ids:
        feedback.append("Error: No ground truth data found.")
        logic_score = 0
    elif not exported_ids:
        feedback.append("Exported CSV is empty or has no recognizable IDs.")
        logic_score = 0
    else:
        tp = len(ground_truth_ids.intersection(exported_ids))
        fp = len(exported_ids - ground_truth_ids)
        fn = len(ground_truth_ids - exported_ids)
        
        if tp == len(ground_truth_ids) and fp == 0:
            logic_score = 40
            feedback.append(f"Perfect reconciliation! Found all {tp} missing transactions.")
        elif tp > 0:
            # Partial credit
            precision = tp / (tp + fp) if (tp + fp) > 0 else 0
            recall = tp / (tp + fn) if (tp + fn) > 0 else 0
            f1 = 2 * (precision * recall) / (precision + recall) if (precision + recall) > 0 else 0
            logic_score = int(40 * f1)
            feedback.append(f"Partial reconciliation. Found {tp}/{len(ground_truth_ids)} missing. (F1: {f1:.2f})")
        else:
            logic_score = 0
            feedback.append("Reconciliation failed. No correct missing IDs found in export.")

    score += logic_score

    # 4. Table Visual (10 pts)
    visuals = [v.lower() for v in result.get('visual_types', [])]
    if any('table' in v or 'pivot' in v for v in visuals):
        score += 10
        feedback.append("Table visual present.")
    else:
        feedback.append("Table visual missing.")

    # 5. Bar Chart (15 pts)
    if any('bar' in v or 'column' in v for v in visuals):
        score += 15
        feedback.append("Bar/Column chart present.")
    else:
        feedback.append("Bar chart missing.")

    # 6. Card Visual (15 pts)
    if any('card' in v for v in visuals):
        score += 15
        feedback.append("Card visual present.")
    else:
        feedback.append("Card visual missing.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }