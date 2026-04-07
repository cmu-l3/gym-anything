#!/usr/bin/env python3
"""
Verifier for Telescope Drift Measurement Task.

Uses programmatic verification to compare the agent's reported drift 
against the mathematically injected ground truth.

Scoring (100 points total):
  1. AIJ Measurement file exists (20 pts) - anti-gaming check
  2. Report format is correct / fields present (10 pts)
  3. delta_x accuracy (35 pts)
  4. delta_y accuracy (35 pts)

Tolerance:
  ±2.0 pixels: Full points
  ±5.0 pixels: Partial points
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_measure_telescope_drift(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Load ground truth JSON
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt = {}
    try:
        copy_from_env("/tmp/tracking_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read ground truth: {e}"}
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    true_dx = gt.get("dx_total", 0.0)
    true_dy = gt.get("dy_total", 0.0)
    
    logger.info(f"Ground Truth Drift -> DX: {true_dx:.2f}, DY: {true_dy:.2f}")

    # Criterion 1: Measurement file exists (Anti-gaming)
    if result.get("measurement_file_exists", False):
        score += 20
        feedback_parts.append(f"AIJ measurements exported ({result.get('measurement_file_name')})")
    else:
        feedback_parts.append("MISSING: AstroImageJ measurement table export")

    # Criterion 2: Report existence and parsing
    if not result.get("report_exists", False):
        feedback_parts.append("MISSING: tracking_drift_report.txt not found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    report_content = result.get("report_content", "")
    
    # Extract values using regex
    def extract_val(key, text):
        match = re.search(rf"{key}\s*[:=]\s*([-+]?\d*\.?\d+)", text, re.IGNORECASE)
        if match:
            return float(match.group(1))
        return None

    reported_dx = extract_val(r"delta_x", report_content)
    reported_dy = extract_val(r"delta_y", report_content)
    
    if reported_dx is not None and reported_dy is not None:
        score += 10
        feedback_parts.append("Report parsed successfully")
    else:
        feedback_parts.append("FAILED: Could not parse delta_x/delta_y from report")
        # Cannot score drift without these
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    logger.info(f"Agent Reported -> DX: {reported_dx}, DY: {reported_dy}")

    # Criterion 3 & 4: Drift accuracy
    def score_drift(axis_name, reported, truth, max_points=35):
        err = abs(reported - truth)
        if err <= 2.0:
            feedback_parts.append(f"{axis_name} drift highly accurate (err {err:.2f}px)")
            return max_points
        elif err <= 5.0:
            feedback_parts.append(f"{axis_name} drift approximate (err {err:.2f}px)")
            return max_points // 2
        else:
            feedback_parts.append(f"{axis_name} drift inaccurate (err {err:.2f}px, expected {truth:.2f})")
            return 0

    score += score_drift("X", reported_dx, true_dx)
    score += score_drift("Y", reported_dy, true_dy)

    # Final pass logic
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }