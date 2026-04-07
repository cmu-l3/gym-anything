#!/usr/bin/env python3
"""
Verifier for Sakila RFM Segmentation Analysis task.

Verifies:
1. `customer_rfm_scores` table exists with 599 rows.
2. Raw RFM metrics (recency, frequency, monetary) are correct.
3. Scoring logic (1-5) is correct, especially Recency directionality.
4. Exported CSV contains correct "High Value Churn Risk" customers.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sakila_rfm_segmentation_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ----------------------------------------------------------------
    # 1. Table Creation & Population (20 pts)
    # ----------------------------------------------------------------
    table_exists = result.get('table_exists', False)
    row_count = result.get('row_count', 0)
    expected_rows = 599
    
    if table_exists:
        if row_count == expected_rows:
            score += 20
            feedback_parts.append("Table created with all 599 customers")
        else:
            score += 10
            feedback_parts.append(f"Table created but has {row_count} rows (expected {expected_rows})")
    else:
        feedback_parts.append("Table `customer_rfm_scores` not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # ----------------------------------------------------------------
    # 2. Raw Metrics Accuracy (20 pts)
    # ----------------------------------------------------------------
    # Using 95% tolerance for floating point diffs or minor calculation discrepancies
    metrics_match = result.get('metrics_match_count', 0)
    match_rate = metrics_match / expected_rows if expected_rows > 0 else 0
    
    if match_rate >= 0.99:
        score += 20
        feedback_parts.append("RFM metrics calculation accurate")
    elif match_rate >= 0.8:
        score += 10
        feedback_parts.append(f"RFM metrics mostly accurate ({int(match_rate*100)}%)")
    else:
        feedback_parts.append(f"RFM metrics calculation failed (only {int(match_rate*100)}% match ground truth)")

    # ----------------------------------------------------------------
    # 3. Scoring Logic - Recency (20 pts)
    # ----------------------------------------------------------------
    # Recency is the hardest: Low Days = High Score (5). 
    # Usually requires ORDER BY DESC in NTILE.
    r_match = result.get('r_score_logic_match', 0)
    r_rate = r_match / expected_rows if expected_rows > 0 else 0
    
    if r_rate >= 0.95:
        score += 20
        feedback_parts.append("Recency scoring logic correct (Low days = High score)")
    else:
        feedback_parts.append(f"Recency scoring logic incorrect ({int(r_rate*100)}% match). Did you handle directionality correctly?")

    # ----------------------------------------------------------------
    # 4. Scoring Logic - Frequency/Monetary (20 pts)
    # ----------------------------------------------------------------
    # Combined score for F and M
    f_match = result.get('f_score_logic_match', 0)
    m_match = result.get('m_score_logic_match', 0)
    avg_fm_rate = ((f_match + m_match) / 2) / expected_rows if expected_rows > 0 else 0
    
    if avg_fm_rate >= 0.95:
        score += 20
        feedback_parts.append("Frequency/Monetary scoring logic correct")
    elif avg_fm_rate >= 0.5:
        score += 10
        feedback_parts.append("Frequency/Monetary scoring logic partially correct")
    else:
        feedback_parts.append("Frequency/Monetary scoring logic incorrect")

    # ----------------------------------------------------------------
    # 5. Export Validation (20 pts)
    # ----------------------------------------------------------------
    file_exists = result.get('file_exists', False)
    csv_rows = result.get('csv_row_count', 0)
    correct_segment = result.get('correct_segment_rows', 0)
    
    # Calculate precision of the export
    # If agent exported 100 rows and 95 are correct according to GT, that's good.
    precision = correct_segment / csv_rows if csv_rows > 0 else 0
    
    if file_exists and csv_rows > 10:
        if precision >= 0.9:
            score += 20
            feedback_parts.append(f"Export correct ({csv_rows} high-risk customers identified)")
        elif precision >= 0.5:
            score += 10
            feedback_parts.append(f"Export mostly correct ({int(precision*100)}% precision)")
        else:
            score += 5
            feedback_parts.append("Export file exists but contains wrong customers")
    elif file_exists:
        feedback_parts.append("Export file exists but is empty or too small")
    else:
        feedback_parts.append("Export file not found")

    # Anti-gaming check
    if not result.get('file_created_during_task', False) and file_exists:
        score = max(0, score - 20)
        feedback_parts.append("WARNING: File not created during task")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }