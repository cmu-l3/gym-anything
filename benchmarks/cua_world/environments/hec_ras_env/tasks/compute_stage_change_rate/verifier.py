#!/usr/bin/env python3
"""
Verifier for compute_stage_change_rate task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compute_stage_change_rate(traj, env_info, task_info):
    """
    Verify the stage change rate calculation.
    
    Criteria:
    1. CSV output exists and has content (20 pts)
    2. CSV was created during the task (10 pts)
    3. CSV row count matches number of cross-sections in HDF5 (10 pts)
    4. Summary file exists and contains parseable values (10 pts)
    5. Overall Max Rise Rate is within 10% of ground truth (25 pts)
    6. Overall Max Fall Rate is within 10% of ground truth (25 pts)
    
    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # 1. Check CSV existence (20 pts)
    if result.get('csv_exists'):
        score += 20
        feedback_parts.append("CSV file created")
    else:
        feedback_parts.append("CSV file missing")
        
    # 2. Check Timestamp (10 pts)
    if result.get('csv_created_during_task'):
        score += 10
        feedback_parts.append("CSV created during task")
    elif result.get('csv_exists'):
        feedback_parts.append("CSV predates task (anti-gaming fail)")
        
    # Get Ground Truth
    gt = result.get('ground_truth', {})
    if 'error' in gt:
        feedback_parts.append(f"Ground Truth Error: {gt['error']}")
        # Fallback if GT failed (unlikely if setup worked)
        gt_num_xs = -1
        gt_rise = -1
        gt_fall = -1
    else:
        gt_num_xs = gt.get('num_cross_sections', -1)
        gt_rise = gt.get('actual_max_rise', -1)
        gt_fall = gt.get('actual_max_fall', -1)
        
    # 3. Check Row Count (10 pts)
    agent_rows = result.get('csv_rows', 0)
    if gt_num_xs > 0:
        # Tolerance of +/- 1 header/footer row mismatch
        if abs(agent_rows - gt_num_xs) <= 1:
            score += 10
            feedback_parts.append(f"CSV row count correct ({agent_rows})")
        else:
            feedback_parts.append(f"CSV row count mismatch (Got {agent_rows}, Expected ~{gt_num_xs})")
    elif agent_rows > 0:
        # Partial credit if we couldn't determine GT but file has data
        score += 5
        feedback_parts.append(f"CSV has data rows ({agent_rows})")
        
    # 4. Check Summary File (10 pts)
    if result.get('summary_exists'):
        score += 10
        feedback_parts.append("Summary file exists")
    else:
        feedback_parts.append("Summary file missing")
        
    # 5. Check Values (50 pts total)
    agent_rise = result.get('agent_max_rise', -1)
    agent_fall = result.get('agent_max_fall', -1)
    
    # Rise Rate (25 pts)
    if gt_rise > 0 and agent_rise > 0:
        diff = abs(agent_rise - gt_rise)
        pct_diff = diff / gt_rise
        if pct_diff <= 0.10: # 10% tolerance
            score += 25
            feedback_parts.append(f"Rise Rate accurate ({agent_rise:.3f} vs {gt_rise:.3f})")
        elif pct_diff <= 0.25: # 25% tolerance for partial credit
            score += 10
            feedback_parts.append(f"Rise Rate close ({agent_rise:.3f} vs {gt_rise:.3f})")
        else:
            feedback_parts.append(f"Rise Rate incorrect ({agent_rise:.3f} vs {gt_rise:.3f})")
    else:
        feedback_parts.append("Rise Rate verification skipped/failed")
        
    # Fall Rate (25 pts)
    if gt_fall > 0 and agent_fall > 0:
        diff = abs(agent_fall - gt_fall)
        pct_diff = diff / gt_fall
        if pct_diff <= 0.10: # 10% tolerance
            score += 25
            feedback_parts.append(f"Fall Rate accurate ({agent_fall:.3f} vs {gt_fall:.3f})")
        elif pct_diff <= 0.25:
            score += 10
            feedback_parts.append(f"Fall Rate close ({agent_fall:.3f} vs {gt_fall:.3f})")
        else:
            feedback_parts.append(f"Fall Rate incorrect ({agent_fall:.3f} vs {gt_fall:.3f})")
    else:
        feedback_parts.append("Fall Rate verification skipped/failed")
        
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }