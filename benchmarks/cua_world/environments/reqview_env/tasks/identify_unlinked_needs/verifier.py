#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_identify_unlinked_needs(traj, env_info, task_info):
    """
    Verify the requirements gap analysis task.
    
    Scoring:
    - 20 pts: Report file exists and modified during task.
    - 60 pts: Accuracy of identified unlinked needs (F1 score).
    - 20 pts: VLM verification of UI interaction.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy capability missing."}

    # Load result metadata from container
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}

    score = 0
    feedback = []

    # 1. File Existence & Timestamp Check (20 pts)
    report_exists = task_result.get("report_exists", False)
    file_ts = task_result.get("file_timestamp", 0)
    start_ts = task_result.get("task_start_time", 0)

    if report_exists and file_ts > start_ts:
        score += 20
        feedback.append("Report file created successfully.")
    else:
        feedback.append("Report file missing or not created during task.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Accuracy Check (60 pts)
    # Fetch Ground Truth
    ground_truth = {"unlinked_needs": []}
    gt_path = task_result.get("ground_truth_path")
    if gt_path:
        with tempfile.NamedTemporaryFile(suffix='.json') as f:
            try:
                copy_from_env(gt_path, f.name)
                f.seek(0)
                ground_truth = json.load(f)
            except Exception as e:
                feedback.append(f"Warning: Could not load ground truth ({str(e)})")

    # Fetch Agent Report
    agent_content = ""
    report_path = task_result.get("report_path")
    with tempfile.NamedTemporaryFile(suffix='.txt') as f:
        try:
            copy_from_env(report_path, f.name)
            f.seek(0)
            agent_content = f.read().decode('utf-8', errors='ignore')
        except:
            pass

    # Extract IDs from agent report (looking for pattern NEEDS-XXX)
    agent_ids = set(re.findall(r'NEEDS-\d+', agent_content))
    true_ids = set(ground_truth.get("unlinked_needs", []))

    if not true_ids:
        # Fallback if ground truth generation failed or produced nothing (shouldn't happen with our setup script)
        feedback.append("Error: Ground truth is empty. Setup may have failed.")
        accuracy_score = 0
    else:
        # Calculate F1
        tp = len(agent_ids.intersection(true_ids))
        fp = len(agent_ids - true_ids)
        fn = len(true_ids - agent_ids)
        
        precision = tp / (tp + fp) if (tp + fp) > 0 else 0
        recall = tp / (tp + fn) if (tp + fn) > 0 else 0
        f1 = 2 * (precision * recall) / (precision + recall) if (precision + recall) > 0 else 0
        
        accuracy_score = int(f1 * 60)
        feedback.append(f"Accuracy: Precision={precision:.2f}, Recall={recall:.2f}, F1={f1:.2f}")
        
        # Bonus for getting at least the count roughly right
        if abs(len(agent_ids) - len(true_ids)) <= 1 and len(true_ids) > 0:
            feedback.append("Count of unlinked needs is correct/close.")

    score += accuracy_score

    # 3. VLM Verification (20 pts)
    # Verify the agent actually looked at the documents
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = (
        "Did the user perform a requirements gap analysis in ReqView? "
        "I need to see: 1. The 'NEEDS' document open. 2. The 'SRS' document open (or traceability columns visible). "
        "3. A text editor being used to write a list of IDs. "
        "Return JSON with 'score_0_to_20' and 'reason'."
    )
    
    vlm_score = 0
    try:
        vlm_res = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        parsed = vlm_res.get('parsed', {})
        vlm_score = min(20, max(0, int(parsed.get('score_0_to_20', 0))))
        feedback.append(f"VLM Analysis: {parsed.get('reason', 'No reasoning provided')}")
    except Exception as e:
        feedback.append(f"VLM check failed: {e}")
        vlm_score = 10 # Grace points if VLM fails

    score += vlm_score

    # Pass Threshold
    # We require decent accuracy (F1 > 0.5 implies score > 30 from accuracy part) + file existence
    passed = (score >= 60) and (report_exists)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "agent_ids": list(agent_ids),
            "ground_truth_ids": list(true_ids),
            "stats": {"tp": tp, "fp": fp, "fn": fn} if true_ids else {}
        }
    }