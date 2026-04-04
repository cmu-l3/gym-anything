#!/usr/bin/env python3
"""
Verifier for compute_heatpump_cop task.
Checks:
1. 'heatpump_cop' feed existence and config.
2. Correctness of computed data in the feed (Math check).
3. Report file content against ground truth.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compute_heatpump_cop(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Helper to safe float conversion
    def safe_float(val):
        try:
            return float(val)
        except (ValueError, TypeError):
            return 0.0

    # 1. Feed Existence (15 pts)
    feed_exists = result.get("feed_exists", False)
    feed_id = result.get("feed_id", "0")
    feed_engine = str(result.get("feed_engine", "0"))
    
    if feed_exists:
        score += 15
        feedback_parts.append("Feed 'heatpump_cop' created.")
        # Check engine (5 is PHPFina, preferred for time series)
        if feed_engine == "5":
            score += 5
            feedback_parts.append("Correct feed engine (PHPFina).")
        else:
            feedback_parts.append(f"Feed engine is {feed_engine} (expected 5/PHPFina).")
    else:
        feedback_parts.append("Feed 'heatpump_cop' NOT found.")
        return {"passed": False, "score": 0, "feedback": "Critical: Feed not created."}

    # 2. Feed Data Content (40 pts)
    feed_stats = result.get("feed_stats", {})
    ground_truth = result.get("ground_truth", {})
    
    gt_count = safe_float(ground_truth.get("count", 0))
    gt_avg = safe_float(ground_truth.get("avg", 0))
    
    actual_count = safe_float(feed_stats.get("count", 0))
    actual_avg = safe_float(feed_stats.get("avg", 0))
    
    # Check data volume (15 pts)
    if gt_count > 0:
        count_ratio = actual_count / gt_count
        if count_ratio >= 0.9:
            score += 15
            feedback_parts.append(f"Data count good ({int(actual_count)} points).")
        elif count_ratio >= 0.5:
            score += 7
            feedback_parts.append(f"Partial data count ({int(actual_count)}/{int(gt_count)}).")
        else:
            feedback_parts.append(f"Insufficient data points ({int(actual_count)}).")
    
    # Check data accuracy (25 pts)
    if actual_count > 0 and gt_avg > 0:
        # Allow 5% deviation on average (rounding diffs)
        avg_diff = abs(actual_avg - gt_avg) / gt_avg
        if avg_diff < 0.05:
            score += 25
            feedback_parts.append(f"COP calculation accurate (Avg: {actual_avg:.2f}).")
        elif avg_diff < 0.15:
            score += 10
            feedback_parts.append(f"COP calculation approximate (Avg: {actual_avg:.2f} vs {gt_avg:.2f}).")
        else:
            feedback_parts.append(f"COP values incorrect (Avg: {actual_avg:.2f} vs {gt_avg:.2f}).")

    # 3. Report File (40 pts)
    report_exists = result.get("report_exists", False)
    report_data = result.get("report_data", {})
    
    if report_exists:
        score += 10
        feedback_parts.append("Report file exists.")
        
        # Line 1: Feed ID
        r_id = str(report_data.get("id", "")).strip()
        if r_id == str(feed_id):
            score += 5
            feedback_parts.append("Report: ID matches.")
        
        # Line 2: Count
        r_count = safe_float(report_data.get("count", 0))
        if abs(r_count - actual_count) < 5:
            score += 5
            feedback_parts.append("Report: Count matches.")
            
        # Line 3: Avg
        r_avg = safe_float(report_data.get("avg", 0))
        if gt_avg > 0 and abs(r_avg - gt_avg) / gt_avg < 0.1:
            score += 10
            feedback_parts.append("Report: Average correct.")
            
        # Line 4/5: Max/Min
        r_max = safe_float(report_data.get("max", 0))
        r_min = safe_float(report_data.get("min", 0))
        gt_max = safe_float(ground_truth.get("max", 0))
        gt_min = safe_float(ground_truth.get("min", 0))
        
        if abs(r_max - gt_max) < 0.5 and abs(r_min - gt_min) < 0.5:
            score += 10
            feedback_parts.append("Report: Min/Max correct.")
    else:
        feedback_parts.append("Report file missing.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }