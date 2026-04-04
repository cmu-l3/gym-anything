#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_dna_cell_cycle_analysis(traj, env_info, task_info):
    """
    Verify DNA Cell Cycle Analysis task.
    
    Scoring:
    1. Artifacts Created (20 pts): Files exist.
    2. Measurement Data (30 pts): CSV valid (>20 cells, Integrated Density col).
    3. Histogram Validity (10 pts): Image exists.
    4. G1 Peak Accuracy (40 pts): Reported value matches ground truth (within 15%).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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
    feedback = []

    # 1. Artifacts & Timestamp (20 pts)
    if result.get("csv_exists") and result.get("report_exists") and result.get("histogram_exists"):
        if result.get("files_created_during_task"):
            score += 20
            feedback.append("All output files created successfully.")
        else:
            score += 10
            feedback.append("Files exist but timestamps are old (re-used previous run?).")
    else:
        feedback.append("Missing one or more output files.")

    # 2. Measurement Data (30 pts)
    csv_rows = result.get("csv_rows", 0)
    has_intden = result.get("has_intden_column", False)
    
    if csv_rows > 20:
        score += 15
        feedback.append(f"Measurement count sufficient ({csv_rows} cells).")
    else:
        feedback.append(f"Insufficient measurements ({csv_rows}). Expected > 20.")
        
    if has_intden:
        score += 15
        feedback.append("Integrated Density column found.")
    else:
        feedback.append("Missing 'Integrated Density' column in measurements.")

    # 3. Histogram (10 pts)
    if result.get("histogram_exists"):
        score += 10
        feedback.append("Histogram image saved.")

    # 4. G1 Peak Accuracy (40 pts)
    reported = float(result.get("reported_peak_value", 0))
    ground_truth = float(result.get("ground_truth_peak", 0))
    
    if ground_truth > 0:
        tolerance = task_info.get("metadata", {}).get("tolerance_percent", 15) / 100.0
        diff = abs(reported - ground_truth)
        percent_diff = diff / ground_truth
        
        if percent_diff <= tolerance:
            score += 40
            feedback.append(f"G1 Peak accurate: {reported:.1f} (Ground Truth: {ground_truth:.1f}).")
        elif percent_diff <= (tolerance * 2): # Partial credit for being close
            score += 20
            feedback.append(f"G1 Peak somewhat accurate: {reported:.1f} (Ground Truth: {ground_truth:.1f}).")
        else:
            feedback.append(f"G1 Peak inaccurate: {reported:.1f} (Ground Truth: {ground_truth:.1f}).")
    else:
        feedback.append("Could not calculate ground truth - verification limited.")
        # If ground truth failed but they did the work, give partial credit
        if reported > 0:
            score += 10

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }