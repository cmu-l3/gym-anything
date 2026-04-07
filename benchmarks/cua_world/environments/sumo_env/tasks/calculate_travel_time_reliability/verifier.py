#!/usr/bin/env python3
"""
Verifier for Calculate Travel Time Reliability Task.

Scoring Breakdown (100 total):
- 30 pts: Simulated correctly (5 valid tripinfo XML files created)
- 10 pts: Report formatted correctly (JSON with required keys)
- 20 pts: Total trip count matches ground truth
- 20 pts: Mean duration matches ground truth (tolerance +/- 0.5s)
- 20 pts: 95th Percentile duration matches ground truth (tolerance +/- 0.5s)

Pass threshold is 70 points.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_calculate_travel_time_reliability(traj, env_info, task_info):
    """Verify that agent executed multiple simulations and aggregated the results accurately."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load exported task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criterion 1: Simulation Execution
    xml_count = result.get("valid_tripinfo_files_count", 0)
    if xml_count >= 5:
        score += 30
        feedback.append(f"Successfully generated {xml_count} tripinfo XML files (30/30 pts).")
    elif xml_count > 0:
        score += xml_count * 6
        feedback.append(f"Partially generated {xml_count} tripinfo XML files ({xml_count * 6}/30 pts).")
    else:
        feedback.append("No tripinfo XML files found in output directory (0/30 pts).")

    # Criterion 2: Report Formatting
    report_exists = result.get("report_exists", False)
    agent_report = result.get("agent_report", {})
    has_keys = False

    if report_exists and isinstance(agent_report, dict):
        keys = ["total_trips", "mean_duration", "p95_duration"]
        if all(k in agent_report for k in keys):
            score += 10
            has_keys = True
            feedback.append("Report JSON exists and is formatted correctly (10/10 pts).")
        else:
            feedback.append(f"Report JSON missing required keys. Found: {list(agent_report.keys())} (0/10 pts).")
    else:
        feedback.append("Report JSON 'reliability_report.json' not found or is invalid (0/10 pts).")

    # Criteria 3-5: Accuracy Checks (Compared to deterministic ground truth)
    gt = result.get("ground_truth", {})
    gt_total = gt.get("total_trips", -1)
    gt_mean = gt.get("mean_duration", -1)
    gt_p95 = gt.get("p95_duration", -1)

    if has_keys and gt_total > 0:
        # Trip Count Accuracy
        try:
            ag_total = float(agent_report.get("total_trips", 0))
            if abs(ag_total - gt_total) < 0.1:
                score += 20
                feedback.append(f"Total trips accurate: {ag_total} (20/20 pts).")
            else:
                feedback.append(f"Total trips inaccurate. Expected {gt_total}, got {ag_total} (0/20 pts).")
        except Exception:
            feedback.append("Total trips value invalid or non-numeric (0/20 pts).")

        # Mean Accuracy
        try:
            ag_mean = float(agent_report.get("mean_duration", 0))
            if abs(ag_mean - gt_mean) <= 0.5:
                score += 20
                feedback.append(f"Mean duration accurate: {ag_mean} (20/20 pts).")
            else:
                feedback.append(f"Mean duration inaccurate. Expected ~{gt_mean:.2f}, got {ag_mean} (0/20 pts).")
        except Exception:
            feedback.append("Mean duration value invalid or non-numeric (0/20 pts).")

        # P95 Accuracy
        try:
            ag_p95 = float(agent_report.get("p95_duration", 0))
            if abs(ag_p95 - gt_p95) <= 0.5:
                score += 20
                feedback.append(f"P95 duration accurate: {ag_p95} (20/20 pts).")
            else:
                feedback.append(f"P95 duration inaccurate. Expected ~{gt_p95:.2f}, got {ag_p95} (0/20 pts).")
        except Exception:
            feedback.append("P95 duration value invalid or non-numeric (0/20 pts).")
    elif not has_keys:
        feedback.append("Metrics not evaluated due to missing/invalid report file (0/60 pts).")
    else:
        feedback.append("Ground truth computation failed; metrics could not be verified (0/60 pts).")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }