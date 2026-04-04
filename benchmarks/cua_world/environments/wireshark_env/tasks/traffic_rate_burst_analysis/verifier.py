#!/usr/bin/env python3
"""
Verifier for Traffic Rate and Burst Analysis Task.
"""

import json
import os
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_traffic_rate_burst_analysis(traj, env_info, task_info):
    """
    Verifies the traffic rate analysis report against the ground truth.
    
    Scoring:
    - 10 pts: Report file exists and created during task.
    - 10 pts: TOTAL_PACKETS matches.
    - 10 pts: CAPTURE_DURATION_SECS matches (+/- 1s).
    - 10 pts: AVERAGE_PPS matches (+/- 0.5).
    - 15 pts: PEAK_PPS matches (+/- 0).
    - 10 pts: PEAK_SECOND matches (+/- 1s).
    - 10 pts: IDLE_SECONDS matches (+/- 1s).
    - 10 pts: BURST_THRESHOLD calculation is correct based on Avg.
    - 10 pts: BURST_COUNT matches (+/- 1).
    - 5 pts: Per-second data section exists.
    
    Total: 100
    Pass Threshold: 60
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy unavailable"}

    # 1. Retrieve Result Metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result metadata: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Check basic file existence (Anti-gaming included)
    if not result_meta.get("report_exists", False):
        return {"passed": False, "score": 0, "feedback": "Report file was not created."}
    
    if not result_meta.get("report_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Report file timestamp is older than task start time (Anti-gaming)."}

    score = 10
    feedback = ["File created successfully (+10)."]

    # 3. Retrieve Agent Report and Ground Truth
    agent_report_path = result_meta.get("report_path")
    ground_truth_path = result_meta.get("ground_truth_path")
    
    agent_text = ""
    ground_truth = {}
    
    # Copy Agent Report
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env(agent_report_path, temp_report.name)
        with open(temp_report.name, 'r') as f:
            agent_text = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to retrieve report content: {str(e)}"}
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)

    # Copy Ground Truth
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(ground_truth_path, temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            ground_truth = json.load(f)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to retrieve ground truth: {str(e)}"}
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    # 4. Parsing Helper
    def get_value(label, text):
        # Matches "LABEL: 123" or "LABEL:123.45"
        pattern = rf"{label}\s*:\s*([\d\.]+)"
        match = re.search(pattern, text, re.IGNORECASE)
        if match:
            return float(match.group(1))
        return None

    # 5. Verification Logic
    
    # TOTAL_PACKETS (10 pts)
    val = get_value("TOTAL_PACKETS", agent_text)
    gt_val = ground_truth["TOTAL_PACKETS"]
    if val is not None and int(val) == gt_val:
        score += 10
        feedback.append(f"Total packets match ({int(val)}) (+10).")
    else:
        feedback.append(f"Total packets mismatch (Exp: {gt_val}, Got: {val}).")

    # CAPTURE_DURATION_SECS (10 pts)
    val = get_value("CAPTURE_DURATION_SECS", agent_text)
    gt_val = ground_truth["CAPTURE_DURATION_SECS"]
    if val is not None and abs(val - gt_val) <= 1:
        score += 10
        feedback.append(f"Duration matches (+10).")
    else:
        feedback.append(f"Duration mismatch (Exp: {gt_val}, Got: {val}).")

    # AVERAGE_PPS (10 pts)
    val = get_value("AVERAGE_PPS", agent_text)
    gt_val = ground_truth["AVERAGE_PPS"]
    if val is not None and abs(val - gt_val) <= 0.5:
        score += 10
        feedback.append(f"Avg PPS matches (+10).")
    else:
        feedback.append(f"Avg PPS mismatch (Exp: {gt_val}, Got: {val}).")

    # PEAK_PPS (15 pts) - Exact match preferred, small tolerance allowed for binning edge cases
    val = get_value("PEAK_PPS", agent_text)
    gt_val = ground_truth["PEAK_PPS"]
    if val is not None and abs(val - gt_val) <= 1:
        score += 15
        feedback.append(f"Peak PPS matches (+15).")
    else:
        feedback.append(f"Peak PPS mismatch (Exp: {gt_val}, Got: {val}).")

    # PEAK_SECOND (10 pts)
    val = get_value("PEAK_SECOND", agent_text)
    gt_val = ground_truth["PEAK_SECOND"]
    if val is not None and abs(val - gt_val) <= 1:
        score += 10
        feedback.append(f"Peak second matches (+10).")
    else:
        feedback.append(f"Peak second mismatch (Exp: {gt_val}, Got: {val}).")

    # IDLE_SECONDS (10 pts)
    val = get_value("IDLE_SECONDS", agent_text)
    gt_val = ground_truth["IDLE_SECONDS"]
    if val is not None and abs(val - gt_val) <= 1:
        score += 10
        feedback.append(f"Idle seconds matches (+10).")
    else:
        feedback.append(f"Idle seconds mismatch (Exp: {gt_val}, Got: {val}).")

    # BURST_THRESHOLD (10 pts)
    val = get_value("BURST_THRESHOLD", agent_text)
    gt_val = ground_truth["BURST_THRESHOLD"]
    if val is not None and abs(val - gt_val) <= 1:
        score += 10
        feedback.append(f"Burst threshold correct (+10).")
    else:
        feedback.append(f"Burst threshold incorrect (Exp: {gt_val}, Got: {val}).")

    # BURST_COUNT (10 pts)
    val = get_value("BURST_COUNT", agent_text)
    gt_val = ground_truth["BURST_COUNT"]
    if val is not None and abs(val - gt_val) <= 1:
        score += 10
        feedback.append(f"Burst count correct (+10).")
    else:
        feedback.append(f"Burst count incorrect (Exp: {gt_val}, Got: {val}).")

    # PER_SECOND_DATA Section Check (5 pts)
    if "PER_SECOND_DATA" in agent_text:
        score += 5
        feedback.append("Data section found (+5).")
    else:
        feedback.append("Missing PER_SECOND_DATA section.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }